# Operations Guide

## Makefile Targets

### Deployment

| Target | Description |
|--------|-------------|
| `make fresh-deploy` | Full deployment from scratch: base image → VMs → cluster → Ceph → HAProxy → services → health check → capture state |
| `make deploy` | Redeploy (skips base image build) |
| `make rebuild` | Tear down and redeploy |
| `make rebuild-clean` | Clear secrets, tear down, and redeploy |

### VM Lifecycle

| Target | Description |
|--------|-------------|
| `make build-base-image` | Build golden Debian 12 VM image |
| `make provision-vms` | Provision 3 VMs from base image |
| `make teardown` | Destroy VMs (prompts for confirmation) |
| `make teardown-force` | Destroy VMs without confirmation |

### Cluster Configuration

| Target | Description |
|--------|-------------|
| `make deploy-cluster` | Run `octant.yml` against cluster nodes |
| `make deploy-host HOST=<name>` | Deploy to a single host |
| `make deploy-role ROLE=<tag>` | Deploy a specific Ansible role |
| `make deploy-role-host ROLE=<tag> HOST=<name>` | Deploy a role to a specific host |

### Infrastructure

| Target | Description |
|--------|-------------|
| `make deploy-ceph` | Deploy Ceph storage cluster |
| `make deploy-haproxy` | Deploy HAProxy on the hypervisor |
| `make remove-haproxy` | Remove HAProxy from the hypervisor |
| `make deploy-volumes` | Create host volume directories |
| `make deploy-services` | Deploy all Terraform service modules |
| `make destroy-services` | Remove all Nomad jobs |

### Operations

| Target | Description |
|--------|-------------|
| `make health-check` | Validate cluster health |
| `make capture-state` | Capture cluster state to `docs/state/` |
| `make seed-secrets` | Seed 1Password secrets into services |
| `make podman-cleanup` | Clean up unused Podman resources |

### Consul and Nomad

| Target | Description |
|--------|-------------|
| `make start-consul` | Start Consul on all nodes |
| `make stop-consul` | Stop Consul on all nodes |
| `make start-consul-host HOST=<name>` | Start Consul on a specific host |
| `make stop-consul-host HOST=<name>` | Stop Consul on a specific host |
| `make reset-consul` | Reset Consul cluster |
| `make start-nomad` | Start Nomad on all nodes |
| `make stop-nomad` | Stop Nomad on all nodes |
| `make start-nomad-host HOST=<name>` | Start Nomad on a specific host |
| `make stop-nomad-host HOST=<name>` | Stop Nomad on a specific host |
| `make reset-nomad` | Reset Nomad cluster |

### Secrets

| Target | Description |
|--------|-------------|
| `make clear-secrets` | Clear vault secrets (prompts for confirmation) |
| `make clear-secrets-force` | Clear vault secrets without confirmation |

### DNS and Terraform

| Target | Description |
|--------|-------------|
| `make tf-update-dns` | Apply DNS terraform module |
| `make tf-update-dns-lab` | Apply lab DNS terraform module |
| `make tf-destroy-dns-lab` | Destroy lab DNS records |

### Utilities

| Target | Description |
|--------|-------------|
| `make check-env` | Verify required environment variables |
| `make lint` | Lint all YAML files with ansible-lint |
| `make install-hashi-cli` | Install HashiCorp CLI tools on hypervisor |

## Deploying a Service

Each service has a Terraform module in `terraform/<service>/`. To deploy or update:

```bash
cd terraform/<service>
terraform init      # First time only
terraform plan      # Preview changes
terraform apply     # Apply changes
```

Terraform state is stored in Consul KV at `terraform/state/<service>`.

## Adding a New Service

1. Copy the template: `cp -r terraform/template terraform/<new-service>`
2. Edit the Nomad job definition in `<new-service>/<new-service>.nomad.hcl`
3. Configure variables in `<new-service>/variables.tf` and `terraform.tfvars`
4. Choose a storage backend:
   - **CephFS:** Add host volumes to `inventory/groups.yml`, run `make deploy-volumes`
   - **CSI RBD:** Create a `<service>-data.hcl` volume definition, run `nomad volume create`
5. Deploy: `cd terraform/<new-service> && terraform init && terraform apply`
6. Verify in Nomad UI and via the service URL

## CSI Volume Management

CSI RBD volumes are dedicated Ceph block devices for databases and high-IO
services. They are managed through the `ceph-csi` Nomad plugin.

### Prerequisites

Verify the CSI plugin is healthy before any volume operations:

```bash
nomad plugin status ceph-csi
```

All 3 nodes should show as healthy controllers and nodes.

### Creating a Volume

1. Create a volume definition file (`terraform/<service>/<service>-data.hcl`):

```hcl
id        = "<service>-data"
name      = "<service>-data"
type      = "csi"
plugin_id = "ceph-csi"

capacity_min = "5GiB"
capacity_max = "5GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  userID  = "nomad-csi"
  userKey = "<key>"    # ceph auth get-key client.nomad-csi
}

parameters {
  clusterID     = "<fsid>"  # ceph fsid
  pool          = "nomad-csi"
  imageFeatures = "layering"
  mkfsOptions   = "-t ext4"
}
```

2. Register the volume:

```bash
nomad volume create terraform/<service>/<service>-data.hcl
```

### Checking Volume Status

```bash
# List all CSI volumes
nomad volume status -type=csi

# Details for a specific volume
nomad volume status -type=csi <volume-id>

# Check underlying RBD images
ssh octant-01 'sudo rbd ls nomad-csi'
ssh octant-01 'sudo rbd info nomad-csi/<image-name>'
```

### Deleting a Volume

Volumes must be detached (no running allocations) before deletion:

```bash
nomad job stop <service>
nomad volume delete -type=csi <volume-id>
```

### Volume Patterns in Job Specs

CSI volumes require the Docker driver on root agents. Every CSI-backed job
follows this pattern:

```hcl
# Root agent constraint (required for CSI)
constraint {
  attribute = "${meta.rootless}"
  value     = "false"
}

# Pin to specific node (required for single-node-writer)
constraint {
  attribute = "${node.unique.name}"
  value     = "octant-01-agent-root"
}

group "<service>" {
  # Declare the CSI volume
  volume "<service>-data" {
    type            = "csi"
    source          = "<service>-data"
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }

  # Prestart task to set ownership (ext4 root is owned by root)
  task "volume-init" {
    driver = "docker"
    lifecycle { hook = "prestart"; sidecar = false }
    volume_mount { volume = "<service>-data"; destination = "/data" }
    config {
      image   = "busybox:latest"
      command = "/bin/sh"
      args    = ["-c", "chown -R <uid>:<gid> /data"]
    }
    resources { cpu = 100; memory = 64 }
  }

  # Main service task
  task "<service>" {
    driver = "docker"
    user   = "<uid>:<gid>"
    volume_mount { volume = "<service>-data"; destination = "/data" }
    # ...
  }
}
```

### Migrating a Service from CephFS to CSI RBD

See `docs/guides/cephfs-to-csi-rbd-migration.md` for the full procedure.
Summary of changes required:

1. Create `<service>-data.hcl` and register the volume
2. Update `.nomad.hcl`: Podman → Docker, rootless → root, host volume → CSI,
   add `volume-init` prestart task, add `node_name` constraint
3. Update `variables.tf`: add `node_name` variable
4. Update `main.tf`: pass `node_name` to `templatefile()`
5. Handle data migration (dump/restore or fresh start)
6. `terraform apply`

**Key differences between Podman and Docker job syntax:**

| Aspect | Podman (CephFS) | Docker (CSI) |
|--------|-----------------|--------------|
| Driver | `"podman"` | `"docker"` |
| Agent | rootless (`meta.rootless = true`) | root (`meta.rootless = false`) |
| User mapping | `userns = "keep-id:uid=N,gid=N"` | `user = "N:N"` (no userns) |
| Volumes | `volumes = ["/mnt/services/...:/data"]` | `volume_mount { ... }` block |
| Logging | `logging = { driver = "journald"; options = [...] }` | `logging { type = "journald"; config { ... } }` |
| Image timeout | `image_pull_timeout = "15m"` | Not needed |

## Playbook Reference

| Playbook | Purpose |
|----------|---------|
| `00-build-base-image.yml` | Build golden VM image on hypervisor |
| `01-provision-vms.yml` | Provision VMs from base image |
| `02-deploy-ceph.yml` | Bootstrap and configure Ceph cluster |
| `02.5-deploy-haproxy.yml` | Deploy HAProxy on hypervisor |
| `02.5-remove-haproxy.yml` | Remove HAProxy from hypervisor |
| `03-deploy-services.yml` | Deploy all Terraform service modules |
| `04-health-check.yml` | Validate cluster health |
| `05-deploy-volumes.yml` | Create host volume directories |
| `06-destroy-services.yml` | Remove all Nomad jobs |
| `07-capture-state.yml` | Capture cluster state |
| `99-teardown.yml` | Destroy VMs and clean up |
| `install-hashi-cli.yml` | Install HashiCorp CLI tools |
| `podman-cleanup.yml` | Clean up Podman resources |

## Common Ansible Operations

### Deploy a specific role to the cluster

```bash
make deploy-role ROLE=consul-server
```

### Deploy to a specific host

```bash
make deploy-host HOST=octant-01
```

### Deploy a role to a specific host

```bash
make deploy-role-host ROLE=nomad-agent HOST=octant-02
```

### Run with verbose output

```bash
make deploy-verbose
```

### Flush Ansible cache and redeploy

```bash
make run-flush-cache
```
