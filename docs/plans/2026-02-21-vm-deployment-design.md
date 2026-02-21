# Octant VM-Based Deployment Design

**Date:** 2026-02-21
**Branch:** TBD (feature branch on octant repo)
**Goal:** Fully automated 3-node Octant cluster deployment on KVM/libvirt VMs with Ceph shared storage

## Context

Octant is a homelab framework built around Consul, Nomad, and Podman. The original deployment targets bare-metal servers. This design adds automated VM provisioning using patterns proven in the eai-cluster project and refined in octant-demo, while preserving `homelab.yml` as the core cluster configuration playbook that works on both VMs and bare metal.

The immediate goal is a working "stock" Octant deployment on VMs that can be torn down and rebuilt repeatedly to validate full automation. Lessons learned will be ported back to octant-private (the production homelab deployment).

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target repo | Branch on octant | Keep public repo as the canonical framework |
| Topology | 3-node cluster (octant-01/02/03) | Matches original Octant architecture |
| Hypervisor | Single KVM host | Simplest starting point |
| Secondary disk | Raw disk, Ceph manages it | cephadm handles formatting and OSD creation |
| Ceph automation | Fully automated via cephadm, semi-auto fallback OK | Pragmatic - automate what works, document the rest |
| Secrets | 1Password + direnv | Production-grade, already proven in octant-private |
| Versions | Configurable with pinned defaults | Reproducible but flexible |
| Initial services | Traefik, Postgres, Registry, LiteLLM | Proven set from octant-demo |

## Playbook Structure (Hybrid Approach)

Numbered playbooks handle VM lifecycle and infrastructure. `homelab.yml` stays at the repo root as the cluster configuration entrypoint, agnostic to whether hosts are VMs or bare metal.

```
playbooks/
  00-build-base-image.yml    # Golden image with packages pre-installed (on hypervisor)
  01-provision-vms.yml        # Create 3 VMs with OS + data disks (on hypervisor)
  02-deploy-ceph.yml          # cephadm bootstrap, OSDs, CephFS, NFS mount (on VMs)
  03-deploy-services.yml      # Terraform modules via apply-terraform role (on VMs)
  04-health-check.yml         # Validate cluster health (on VMs)
  99-teardown.yml             # Destroy VMs and clean up (on hypervisor)
  site.yml                    # Orchestrator: 00 -> 01 -> homelab.yml -> 02 -> 03 -> 04

homelab.yml                   # Cluster config: requirements, consul, nomad, podman
                              # Works on VMs (via site.yml) OR bare-metal hosts
```

### site.yml Orchestration

1. Build base image (skipped if already exists)
2. Provision 3 VMs from base image
3. Import and run `homelab.yml` against provisioned VMs
4. Deploy Ceph on secondary disks
5. Deploy Terraform service modules
6. Run health checks

### 99-teardown.yml Flow

1. Stop Nomad jobs
2. Stop Consul/Nomad services
3. Unmount CephFS
4. Destroy Ceph cluster (cephadm rm-cluster)
5. Destroy VMs (virsh destroy + undefine)
6. Remove VM disks
7. Optionally preserve base image

## Inventory Structure

### hypervisors.yml.example

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

### groups.yml.example

```yaml
all:
  children:
    servers:
      hosts:
        octant-01:
          server: true
          dnsserver: true
          region: home
        octant-02:
          server: true
          dnsserver: true
          region: home
        octant-03:
          server: true
          dnsserver: true
          region: home
      vars:
        vm_ram_gb: 8
        vm_vcpus: 2
        vm_os_disk_size: 50G
        vm_data_disk_size: 100G
```

### group_vars/all.yml Additions

- Consul/Nomad version pins with override capability
- Ceph configuration (pool size, CephFS name, mount path)
- Base image naming
- 1Password vault references

Existing config (configdirs, datadirs, consul/nomad ports, volumes) stays as-is.

## Roles

### New Roles

| Role | Source | Purpose |
|------|--------|---------|
| `vm_storage` | octant-demo / eai-cluster | Create OS disk (qcow2 from base) + raw data disk |
| `vm_provision` | octant-demo / eai-cluster | Cloud-init ISO, libvirt domain, VM startup, SSH wait |
| `ceph` | New | cephadm bootstrap, host add, OSD, CephFS, NFS mount |
| `apply-terraform` | octant-demo | Modular Terraform orchestration with execution ordering |
| `secrets` | octant-private pattern | 1Password + direnv integration |

### Updated Roles

| Role | Changes |
|------|---------|
| `requirements` | Version pinning for HashiCorp packages, add `changed_when` to shell tasks |
| `install-hashi` | Support pinned version variables |
| `volumes` | Work on CephFS-mounted `/mnt/services` (create subdirs, not mount points) |

### Existing Roles (Unchanged)

consul-server, consul-agent, consul-agent-root, nomad-server, nomad-agent, nomad-agent-root, configure-consul, configure-nomad, podman-root, podman-rootless, tailscale, restic, docker, server-update

## Ceph Deployment Flow (02-deploy-ceph.yml)

### Stage 1: Bootstrap (octant-01)
- Install cephadm via APT
- `cephadm bootstrap --mon-ip <ip> --skip-monitoring-stack --single-host-defaults`
- Copy ceph SSH key to other nodes

### Stage 2: Add Hosts (from octant-01)
- `ceph orch host add octant-02 <ip>` and `octant-03 <ip>`
- Wait for 3-monitor quorum
- `ceph orch apply mon --placement="octant-01,octant-02,octant-03"`

### Stage 3: Add OSDs
- Each node's `/dev/vdb` (raw data disk) auto-detected by cephadm
- `ceph orch apply osd --all-available-devices`
- Wait for OSD activation and replication

### Stage 4: Create CephFS
- `ceph fs volume create octant-services`
- Adjust pool replication to 2 for 3-node cluster

### Stage 5: Mount on All Nodes
- Get ceph auth key
- Mount CephFS at `/mnt/services` via `/etc/fstab`
- Verify cross-node read/write

### Fallback
If any cephadm step proves unreliable in automation, that step gets a documented manual command and a verification task. The playbook remains runnable with manual intervention points clearly marked.

## Service Deployment (03-deploy-services.yml)

Uses `apply-terraform` role with execution order:

1. **Traefik** - Reverse proxy, must be first
2. **Postgres** - Database, data on CephFS
3. **Registry** - Container image cache, useful across 3 nodes
4. **LiteLLM** - LLM proxy, validates full stack

Terraform state stored in Consul KV at `terraform/state/<service>`.

Nomad jobs schedule across the 3-node cluster with CephFS-backed volumes, so jobs can migrate between nodes without data loss.

## File Layout

```
octant/
├── homelab.yml
├── playbooks/
│   ├── 00-build-base-image.yml
│   ├── 01-provision-vms.yml
│   ├── 02-deploy-ceph.yml
│   ├── 03-deploy-services.yml
│   ├── 04-health-check.yml
│   ├── 99-teardown.yml
│   └── site.yml
├── roles/
│   ├── vm_storage/
│   ├── vm_provision/
│   ├── ceph/
│   ├── apply-terraform/
│   ├── secrets/
│   ├── requirements/          (updated)
│   ├── install-hashi/         (updated)
│   ├── volumes/               (updated)
│   ├── consul-server/
│   ├── consul-agent/
│   ├── consul-agent-root/
│   ├── nomad-server/
│   ├── nomad-agent/
│   ├── nomad-agent-root/
│   ├── configure-consul/
│   ├── configure-nomad/
│   ├── podman-root/
│   ├── podman-rootless/
│   ├── tailscale/
│   ├── restic/
│   ├── docker/
│   └── server-update/
├── terraform/
│   ├── traefik/
│   ├── postgres/
│   ├── registry/
│   └── litellm/
├── inventory/
│   ├── hypervisors.yml.example
│   ├── groups.yml.example
│   └── group_vars/
│       ├── all.yml.example
│       └── hypervisors.yml
├── docs/
│   └── plans/
├── Makefile
└── .envrc
```

---

## Assessment: What Octant Got Right

**The architecture is genuinely good.** The 3-node Consul/Nomad quorum with server/agent separation, TLS everywhere, and gossip encryption is production-grade distributed systems design. Most homelab projects skip the hard parts. Octant built the real thing.

**The port allocation scheme is systematic.** 8500/9500/10500 for server/agent/root-agent across both Consul and Nomad is predictable and easy to reason about.

**Rootless + root Podman was the right call.** Paired Consul+Nomad agents for each mode (rootless default, root when needed) is clean security-conscious design that most homelab projects skip entirely.

**Terraform for Nomad jobs with Consul state backend.** Plan/apply workflow for service definitions with state stored inside the cluster it manages. Shows real understanding of the tooling.

**Tailscale for multi-region.** Pragmatic engineering - one tool that does VPN mesh extremely well, no complex infrastructure needed.

**The `/mnt/services/*` convention.** Consistent, pre-created directory structure for service data. Simple, predictable, backup-friendly.

**Disciplined iterative evolution.** octant -> octant-demo -> octant-private -> eai-cluster. Each iteration solved real problems without abandoning the core architecture.

## Assessment: What Could Be Improved

**Hardcoded values throughout roles.** nomad-driver-podman v0.5.2 hardcoded in 3 roles. HashiCorp APT URL repeated. These work until you need to change them, then it's a hunt.

**Code duplication between agent roles.** consul-agent and consul-agent-root are ~80% identical. Same for nomad-agent/nomad-agent-root. Could be one parameterized role (install-hashi started down this path but didn't finish).

**Shell tasks without `changed_when`.** Heavy use of `shell`/`command` modules without change detection. Every run shows "changed" for idempotent tasks, making diff output untrustworthy during rebuild cycles.

**DNS strategy inconsistency.** Public octant uses dnsmasq. Octant-demo uses systemd-resolved. Octant-private uses dnsmasq again. Needs one settled approach.

**In-band TLS certificate generation.** Running `consul tls ca create` during playbook runs means every fresh deployment gets a new CA. Works but makes rotation painful (18 cert management Makefile targets in octant-private).

**No input validation.** Missing required variables produce cryptic Jinja2 errors mid-run. A few `assert` tasks at the top of key roles would catch problems early.

**Documentation consistently deprioritized.** README has 8 TODOs. Every role has a documentation TODO. The code is readable - it just needs the "why" alongside the "what."

**Makefile grew organically.** octant-private hit 7,000+ lines. Functional but unstructured. The public framework should have a lean, well-organized set of core targets.

**Three generations of secrets management.** .secrets.yml -> .env -> 1Password+direnv. Healthy experimentation, but the public repo still has the oldest approach. Time to settle.

**Packer and cloud-init overlap.** Both create golden images with different tooling. For VM deployment, cloud-init is simpler and doesn't require Packer as a dependency.

## Net Assessment

The core architecture holds up well after two years. The issues are implementation-layer concerns - duplication, hardcoding, missing validation, documentation gaps. These are exactly the kinds of things that accumulate in a working personal project where shipping and learning take priority over polish. None are architectural problems, and they're all addressable during this refresh.
