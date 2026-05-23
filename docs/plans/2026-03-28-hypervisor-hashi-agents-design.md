# Hypervisor Nomad & Consul Agents - Design

**Date:** 2026-03-28
**Branch:** `feat/ansible` (cluster-bloom) / `feature/vm-deployment` (octant worktree)
**Status:** Draft

## Goal

Install root Consul and Nomad client agents on the KVM hypervisor host so it joins the existing 3-node VM cluster as a client node, primarily to enable testing of the `nomad-device-amdgpu` plugin without SR-IOV/GPU-connected VMs.

## Context

The Octant VM cluster runs 3 VMs (octant-01/02/03) managed by a KVM hypervisor. All Consul/Nomad roles currently target the VM hosts. The hypervisor is already in the `hypervisors` inventory group and runs HAProxy, but has no Hashi agent services.

**Primary use case:** Test `nomad-device-amdgpu` (and potentially `nomad-device-nvidia`) on the hypervisor's physical GPUs without needing GPU passthrough to a VM. Secondary use cases include limited demo scenarios and one-off management jobs that need host hardware access.

Because this is an **occasional-use, test-oriented** setup:

- **Root-only** — skip the rootless `consul-agent` / `nomad-agent` pair entirely. The root agents are sufficient for the device plugin use case.
- **Default Hashi file paths** — use the standard locations that the HashiCorp APT packages create out of the box (`/etc/consul.d/`, `/opt/consul/`, `/etc/nomad.d/`, `/opt/nomad/`). This avoids needing the `configdirs`/`datadirs` map entries in `all.yml` that the existing roles depend on.
- **New standalone playbooks** — rather than shoehorning this into the existing VM-targeted roles, write two focused playbooks (`11-join-hypervisor.yml` / `12-remove-hypervisor.yml`) that handle everything inline without role dependencies that assume a full cluster node context.

The `hashi` user is not needed since we run as root. The `consul` and `nomad` system users created by the APT packages are fine.

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │           KVM Hypervisor             │
                    │         10.216.113.177               │
                    │                                      │
                    │  consul   (client, port 8500)        │
                    │  nomad    (client, port 4646)        │
                    │                                      │
                    │  nomad-device-amdgpu plugin          │
                    │  (accesses /dev/kfd, /dev/dri/*)     │
                    │                                      │
                    │  [HAProxy - already present]         │
                    └──────────────┬──────────────────────┘
                                   │ retry_join → :8301
                    ┌──────────────▼──────────────────────┐
                    │         Consul Cluster (servers)     │
                    │  octant-01  octant-02  octant-03     │
                    │     :8300      :8300      :8300      │
                    └──────────────────────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │         Nomad Cluster (servers)      │
                    │  octant-01  octant-02  octant-03     │
                    │     :4647      :4647      :4647      │
                    └──────────────────────────────────────┘

File paths (APT package defaults, no symlinks or custom dirs):
  /etc/consul.d/consul.hcl        ← generated config
  /opt/consul/                    ← data dir
  /etc/nomad.d/nomad.hcl          ← generated config
  /opt/nomad/                     ← data dir
  /etc/systemd/system/consul.service   ← installed by APT package
  /etc/systemd/system/nomad.service    ← installed by APT package

Ports (use standard defaults — no conflict since HAProxy listens on :443/:4646/:8500
as a proxy, not a local service):
  Consul: HTTP 8500, DNS 8600, gRPC 8502, Serf 8301/8302
  Nomad:  HTTP 4646, RPC 4647, Gossip 4648
```

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Root-only (no rootless agents) | Yes | Device plugins run as root; simpler for test/dev use |
| Default APT file paths | Yes | Avoids `configdirs`/`datadirs` map dependency; packages own the paths |
| Standard ports (8500, 4646) | Yes | No competing services on those ports on the hypervisor |
| Standalone playbooks (no role reuse) | Yes | Existing roles assume full cluster-node context; inline tasks are cleaner for a narrow use case |
| TLS/gossip | Same gossip key + CA as cluster | Hypervisor joins as a peer, not a separate DC |
| `retry_join` | VM IPs on port 8301 | Same join pattern as VM agents |
| Nomad client metadata | `hypervisor = "true"` | Allows device plugin jobs to target this node via constraint |
| No CephFS mount | Skip | Circular dependency (hypervisor manages VMs that host Ceph) |
| Teardown integration | Stop agents in `99-teardown.yml` | Prevent hung cluster state when VMs (servers) are destroyed |
| `plugin_dir` | `/opt/nomad/plugins/` (APT default) | Nomad discovers `amd-gpu` wrapper by filename in this dir; matches README deployment steps |
| amdgpu driver prerequisite | Documented, not automated | `cat /sys/module/amdgpu/initstate` must return `live`; driver load is OS-level, out of playbook scope |

## What Gets Changed

| Component | Current State | Target State | Notes |
|-----------|--------------|--------------|-------|
| `playbooks/11-join-hypervisor.yml` | Does not exist | New — install + configure + start consul + nomad | Inline tasks, no role deps |
| `playbooks/12-remove-hypervisor.yml` | Does not exist | New — stop + clean up consul + nomad | Inline tasks |
| `playbooks/99-teardown.yml` | Destroys VMs only | Pre-step: stop hypervisor agents | Extend existing |
| `Makefile` | No hypervisor-agent targets | Add `join-hypervisor`, `remove-hypervisor` | |
| `inventory/hypervisors.yml` | HAProxy/VM vars only | Add `region: home`, `server: false` | Minimal additions |
| `playbooks/templates/consul-hypervisor.hcl.j2` | Does not exist | New Consul client config template | Separate from VM agent templates |
| `playbooks/templates/nomad-hypervisor.hcl.j2` | Does not exist | New Nomad client config template | Includes `plugin_dir`, `plugin "amd-gpu"` stanza |

No changes to existing roles, `group_vars/all.yml`, `configdirs`/`datadirs`, or VM playbooks.

## Implementation Sections

### Section 1: Inventory additions

`inventory/hypervisors.yml` — add the vars needed by the config templates:

```yaml
all:
  children:
    hypervisors:
      hosts:
        my-hypervisor:
          ansible_host: 10.216.113.177
          ansible_connection: local
          libvirt_images_path: /var/lib/libvirt/images
          data_disk_pool_path: /var/lib/libvirt/images
          libvirt_network: default
          base_image_name: octant-base
          # Hashi agent join config
          region: home
          server: false
          # Path to nomad-device-amdgpu checkout on the hypervisor (binary must be pre-built)
          amdgpu_plugin_repo_dir: /home/melliott/git/nomad-device-amdgpu
```

`datacenter` and `consul_gossip_key` come from `group_vars/all.yml` already.
`groups.servers` (used in `retry_join` template logic) already contains octant-01/02/03.

### Section 2: `playbooks/11-join-hypervisor.yml`

Single play targeting `hypervisors`. All tasks inline — no `include_role`.

**Play structure:**

1. **Ensure HashiCorp APT repo** — same repo setup as `roles/requirements` but inlined
2. **Install consul + nomad packages** (latest or pinned via `consul_version` / `nomad_version`)
3. **Distribute TLS certs** — copy from controller's `files/tls/` to `/etc/consul.d/tls/`
4. **Write `/etc/consul.d/consul.hcl`** from template
5. **Enable + start consul** — `systemd: name=consul enabled=true state=started`
6. **Wait for consul** on port 8500
7. **Write `/etc/nomad.d/nomad.hcl`** from template
8. **Enable + start nomad** — `systemd: name=nomad enabled=true state=started`
9. **Wait for nomad** on port 4646
10. **Verify** — `consul members` and `nomad node status` show hypervisor as client

**`/etc/consul.d/consul.hcl` template (inline or `playbooks/templates/`):**

```hcl
node_name  = "{{ inventory_hostname.split('.')[0] }}"
server     = false
datacenter = "{{ datacenter }}"
data_dir   = "/opt/consul"

client_addr    = "0.0.0.0"
bind_addr      = "0.0.0.0"
advertise_addr = "{{ ansible_default_ipv4.address }}"

{% if consul_gossip_key is defined %}
encrypt                  = "{{ consul_gossip_key }}"
encrypt_verify_incoming  = true
encrypt_verify_outgoing  = true
{% endif %}

tls {
  defaults {
    ca_file   = "/etc/consul.d/tls/consul-agent-ca.pem"
    cert_file = "/etc/consul.d/tls/{{ datacenter }}-client-consul-0.pem"
    key_file  = "/etc/consul.d/tls/{{ datacenter }}-client-consul-0-key.pem"
    verify_incoming        = false
    verify_outgoing        = true
    verify_server_hostname = true
  }
}

retry_join = [
{% for host in groups.servers %}
{% if hostvars[host]['server'] | default(false) %}{% if not loop.first %}, {% endif %}"{{ host }}:8301"{% endif %}
{% endfor %}
]

log_level        = "INFO"
enable_syslog    = true
leave_on_terminate  = false
rejoin_after_leave  = true
```

**`/etc/nomad.d/nomad-hypervisor.hcl` template (`playbooks/templates/nomad-hypervisor.hcl.j2`):**

```hcl
name       = "{{ inventory_hostname.split('.')[0] }}"
data_dir   = "/opt/nomad"
datacenter = "{{ datacenter }}"
region     = "{{ region }}"
bind_addr  = "0.0.0.0"
log_level  = "info"

# plugin_dir and plugin stanzas must be top-level in Nomad 1.11+
# (not nested inside client {})
plugin_dir = "/opt/nomad/plugins"

plugin "amd-gpu" {
  config {
    enabled            = true
    fingerprint_period = "1m"
    force_sysfs_only   = false
  }
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

server {
  enabled = false
}

consul {
  auto_advertise   = true
  server_auto_join = true
  client_auto_join = true
  address          = "127.0.0.1:8500"
  grpc_address     = "127.0.0.1:8502"
  ssl              = false
}

telemetry {
  publish_allocation_metrics = true
  publish_node_metrics       = true
  prometheus_metrics         = true
}

client {
  enabled = true

  meta {
    hypervisor = "true"
  }
}
```

> **Important (Nomad 1.11+):** `plugin_dir` and `plugin "..."` stanzas are top-level — they must **not** be nested inside `client {}`. See `nomad-device-amdgpu` README.

**Plugin wrapper prerequisite — step added to `11-join-hypervisor.yml`:**

The play must create `/opt/nomad/plugins/amd-gpu` (the wrapper script) **before** starting Nomad, because Nomad scans `plugin_dir` at startup. The wrapper filename must exactly match the `plugin "amd-gpu"` stanza name or Nomad skips loading it with: `plugin not referenced in the agent configuration file, loading skipped`.

The play adds a task:

```yaml
- name: Create /opt/nomad/plugins directory
  ansible.builtin.file:
    path: /opt/nomad/plugins
    state: directory
    mode: "0755"

- name: Install amd-gpu plugin wrapper
  ansible.builtin.copy:
    dest: /opt/nomad/plugins/amd-gpu
    mode: "0755"
    content: |
      #!/bin/bash
      REPO_DIR="{{ amdgpu_plugin_repo_dir }}"
      export LD_LIBRARY_PATH="${REPO_DIR}/.build:/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH}"
      exec "${REPO_DIR}/nomad-device-amdgpu" "$@"
```

`amdgpu_plugin_repo_dir` defaults to `/home/{{ ansible_user }}/git/nomad-device-amdgpu` and should be set in `inventory/hypervisors.yml` to match the actual checkout path. The plugin binary must be pre-built (`make build` or `make build-sysfs` in that repo) before running `make join-hypervisor`.

**Revised play structure for `11-join-hypervisor.yml`:**

1. **Assert prerequisites** — check `amdgpu_plugin_repo_dir/nomad-device-amdgpu` binary exists; fail fast with a clear message if not
2. **Assert amdgpu driver is loaded** — `cat /sys/module/amdgpu/initstate` must return `live`
3. **Ensure HashiCorp APT repo** — same repo setup as `roles/requirements` but inlined
4. **Install consul + nomad packages** (latest or pinned via `consul_version` / `nomad_version`)
5. **Distribute TLS certs** — copy from controller's `files/tls/` to `/etc/consul.d/tls/`
6. **Write `/etc/consul.d/consul-hypervisor.hcl`** from template
7. **Enable + start consul** — `systemd: name=consul enabled=true state=started`
8. **Wait for consul** on port 8500
9. **Create `/opt/nomad/plugins/`** directory
10. **Write `/opt/nomad/plugins/amd-gpu`** wrapper script
11. **Write `/etc/nomad.d/nomad-hypervisor.hcl`** from template
12. **Enable + start nomad** — `systemd: name=nomad enabled=true state=started`
13. **Wait for nomad** on port 4646
14. **Verify** — `consul members` and `nomad node status` show hypervisor as client

### Section 3: `playbooks/12-remove-hypervisor.yml`

Single play targeting `hypervisors`. Gracefully removes agents without touching the VM cluster.

**Play structure:**

1. **Drain Nomad node** — `nomad node drain -enable -yes <node-id>` (with short deadline; OK to skip if cluster is already down)
2. **Stop nomad** — `systemd: name=nomad state=stopped enabled=false`
3. **Leave Consul** — `consul leave -http-addr=http://127.0.0.1:8500` (ignore errors if already stopped)
4. **Stop consul** — `systemd: name=consul state=stopped enabled=false`
5. **Remove config files** — delete `/etc/consul.d/consul-hypervisor.hcl`, `/etc/nomad.d/nomad-hypervisor.hcl`, TLS certs in `/etc/consul.d/tls/`, and `/opt/nomad/plugins/amd-gpu` wrapper
6. **Purge data dirs** (optional, gated by `purge_data | default(false)`) — wipe `/opt/consul` and `/opt/nomad`
7. **Optionally uninstall packages** (gated by `uninstall_packages | default(false)`) — `apt remove consul nomad`

Packages, systemd units, and the plugin binary in `amdgpu_plugin_repo_dir` are left installed by default so re-joining is fast (`make join-hypervisor` just rewrites config and restarts).

### Section 4: `playbooks/99-teardown.yml` extension

Prepend a play before the VM destroy steps:

```yaml
- name: Stop hypervisor Hashi agents before destroying cluster servers
  hosts: hypervisors
  become: true
  tasks:
    - name: Stop Nomad on hypervisor
      ansible.builtin.systemd:
        name: nomad
        state: stopped
      ignore_errors: true

    - name: Stop Consul on hypervisor
      ansible.builtin.systemd:
        name: consul
        state: stopped
      ignore_errors: true
```

`ignore_errors: true` ensures teardown continues even if the hypervisor agents were never started.

### Section 5: Makefile targets

```makefile
join-hypervisor: ## Install Consul/Nomad agents on hypervisor and join VM cluster
	ansible-playbook -i inventory/ playbooks/11-join-hypervisor.yml $(ANSIBLE_ARGS)

remove-hypervisor: ## Stop and clean up Consul/Nomad agents on hypervisor
	ansible-playbook -i inventory/ playbooks/12-remove-hypervisor.yml $(ANSIBLE_ARGS)
```

## Non-Goals

- Rootless agents on the hypervisor
- Custom config/data paths (use APT defaults)
- ACL tokens
- CephFS mount on hypervisor
- Building the `nomad-device-amdgpu` binary (must be pre-built via `make build` or `make build-sysfs` in that repo before running this playbook)
- ROCm installation (must be pre-installed on the hypervisor for full goamdsmi telemetry; sysfs-only build works without it)
- amdgpu kernel driver installation (must be loaded: `cat /sys/module/amdgpu/initstate` → `live`)
- Multi-hypervisor support (single hypervisor is the current target; `hypervisors` group supports it naturally if needed)

## Validation

**Prerequisites (manual, before running playbook):**

```bash
# 1. amdgpu driver loaded on hypervisor
cat /sys/module/amdgpu/initstate
# Expected: live

# 2. Plugin binary built in nomad-device-amdgpu repo
ls -la ~/git/nomad-device-amdgpu/nomad-device-amdgpu
# Expected: binary present

# 3. VM cluster is up (consul/nomad servers running on octant-01/02/03)
consul members -http-addr=http://192.168.122.101:8500 | grep server
```

**After `make join-hypervisor`:**

```bash
# Consul: hypervisor appears as a live client member
consul members -http-addr=http://192.168.122.101:8500
# Expected: my-hypervisor  10.216.113.177:8301  alive  client  ...

# Nomad: hypervisor appears as a ready client node
nomad node status -address=http://192.168.122.101:4646
# Expected: my-hypervisor  <id>  ready  ...

# Nomad: hypervisor meta tag present
nomad node status -address=http://192.168.122.101:4646 <node-id> | grep hypervisor
# Expected: Meta.hypervisor = true

# Device plugin: AMD GPU fingerprinted
nomad node status -self -verbose | grep -A 20 "Device Group"
# Expected:
#   Device Group Attributes
#   Device Group   = amd/gpu/<product name>
#   driver_version = <kernel amdgpu version>
#   memory         = <N> MiB

# Smoke test: raw_exec job targeting hypervisor
nomad job run -address=http://192.168.122.101:4646 - <<'EOF'
job "hypervisor-test" {
  type = "batch"
  constraint {
    attribute = "${meta.hypervisor}"
    value     = "true"
  }
  group "test" {
    task "hostname" {
      driver = "raw_exec"
      config { command = "/bin/hostname" }
    }
  }
}
EOF
# Expected: allocation runs on hypervisor node, output is hypervisor hostname

# GPU job test: schedule a job requesting 1 AMD GPU
nomad job run -address=http://192.168.122.101:4646 - <<'EOF'
job "gpu-test" {
  type = "batch"
  constraint {
    attribute = "${meta.hypervisor}"
    value     = "true"
  }
  group "test" {
    task "gpu-check" {
      driver = "raw_exec"
      config { command = "/bin/bash"
               args    = ["-c", "echo ROCR_VISIBLE_DEVICES=$ROCR_VISIBLE_DEVICES"] }
      resources {
        device "amd/gpu" { count = 1 }
      }
    }
  }
}
EOF
# Expected: allocation runs on hypervisor, ROCR_VISIBLE_DEVICES=<N> printed
# /dev/kfd and /dev/dri/renderD<N> mounted in alloc environment
```

**After `make remove-hypervisor`:**

```bash
consul members -http-addr=http://192.168.122.101:8500
# Expected: my-hypervisor absent or status = left

nomad node status -address=http://192.168.122.101:4646
# Expected: my-hypervisor absent or status = down
```
