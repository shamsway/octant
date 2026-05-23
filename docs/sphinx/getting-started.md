# Getting Started

## Prerequisites

You need the following on your workstation:

- **KVM hypervisor** with libvirt and virt-install
- **Ansible** (with `ansible-playbook` and `ansible-lint`)
- **Terraform** (for service deployment)
- **direnv** (for environment/secrets management)
- **1Password CLI** (`op`) for secrets
- **SSH access** to the hypervisor and cluster nodes

## Clone and Configure

```bash
git clone https://github.com/your-org/octant.git
cd octant
```

### Inventory Setup

Copy the example inventory files and customize:

```bash
cp inventory/hypervisors.yml.example inventory/hypervisors.yml
cp inventory/groups.yml.example inventory/groups.yml
```

Edit `inventory/hypervisors.yml` to point to your KVM host:

```yaml
all:
  children:
    hypervisors:
      hosts:
        my-hypervisor:
          ansible_host: 192.168.1.10
          libvirt_images_path: /var/lib/libvirt/images
          data_disk_pool_path: /var/lib/libvirt/images
          libvirt_network: default
```

### Secrets Setup

Configure direnv to load secrets from 1Password:

```bash
direnv allow
```

Verify the `TAILSCALE_CLOUD_KEY` and other required variables are set:

```bash
make check-env
```

## First Deploy

The full deployment from scratch uses:

```bash
make fresh-deploy
```

This runs the following targets in sequence:

| Step | Target | What It Does |
|------|--------|--------------|
| 1 | `build-base-image` | Creates a golden Debian 12 VM image with packages pre-installed |
| 2 | `provision-vms` | Provisions 3 VMs from the base image via cloud-init |
| 3 | `deploy-cluster` | Runs `octant.yml` to configure Consul, Nomad, Podman, Tailscale |
| 4 | `deploy-ceph` | Bootstraps Ceph, adds OSDs, creates CephFS, mounts on all nodes |
| 5 | `deploy-haproxy` | Installs HAProxy on the hypervisor for external access |
| 6 | `deploy-services` | Deploys Nomad jobs via Terraform modules |
| 7 | `health-check` | Validates cluster health |
| 8 | `capture-state` | Captures cluster state to `docs/state/lab-state.json` |

## Verify the Deployment

### Health Check

```bash
make health-check
```

This runs the `04-health-check.yml` playbook, which validates:
- Consul cluster membership and leader election
- Nomad server connectivity
- Ceph cluster health (`HEALTH_OK`)
- Service availability

### Check Monitoring

- **Gatus:** `https://gatus.lab.shamsway.net` — monitors 11 endpoints across monitoring, infrastructure, and app groups
- **Grafana:** `https://grafana.lab.shamsway.net` — dashboards for metrics, logs, and traces

### Capture State

```bash
make capture-state
```

Generates `docs/state/lab-state.json` and `docs/state/lab-state.md` with the current
cluster state including versions, running jobs, and image drift detection.

## Subsequent Deploys

After the initial deployment, use `make deploy` (skips base image build):

```bash
make deploy
```

To update a single service:

```bash
cd terraform/<service> && terraform apply
```

To rebuild from scratch (destroys everything first):

```bash
make rebuild-clean
```
