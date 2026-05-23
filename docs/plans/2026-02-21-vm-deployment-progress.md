# Octant VM Deployment - Progress Tracker

**Branch:** `feature/app-migration` (based on `feature/vm-deployment`)
**Worktree:** `/home/melliott/git/octant/.worktrees/vm-deployment`
**Updated:** 2026-02-25

## Phase Status

| Phase | Status | Notes |
|-------|--------|-------|
| 00 - Build base image | DONE | 1.23 GB, Debian 12, all packages verified |
| 01 - Provision VMs | DONE | 3 VMs, DHCP reservations, SSH working |
| 02 - Deploy cluster (octant.yml) | DONE | All 6 services on all 3 nodes |
| 03 - Deploy Ceph | DONE | 3 OSDs, CephFS mounted on all nodes at /mnt/services |
| 04 - Deploy services | DONE | 18 core modules apply + deploy; litellm moved to optional (needs API keys) |
| 05 - Health check | DONE | Infrastructure + service registration checks with retry logic |
| 06 - App migration | DONE | 25 apps migrated, core services running, HTTPS verified end-to-end |
| 99 - Teardown | WORKING | `make rebuild`, `make rebuild-clean`, `make destroy-services` |

## Current State

- **Consul:** 3 servers running, all agents (user + root) active on all 3 nodes
- **Nomad:** 3 servers running, all agents (user + root) active on all 3 nodes, leader elected
- **Ceph:** HEALTH_OK, 3 OSDs, CephFS "octant-services" mounted at /mnt/services (300 GiB)
- **Services (terraform):** 18 core modules deployed via terraform (litellm moved to optional)
- **Services (runtime):** Core services deploying to Nomad, minor service-level issues being resolved
- **1Password:** SaaS auth via service account token, vault "Octant", seed-onepassword role operational
- **Terraform:** Runs locally on controller, targets cluster APIs at 192.168.122.101
- **Domain:** lab.shamsway.net with Cloudflare certresolver configured and working
- **HTTPS:** Let's Encrypt certs via Cloudflare DNS-01 challenge for all 12 services
- **Cloudflare creds:** Sourced from 1Password (`api_cloudflare_key` in Octant vault) via Terraform provider
- **Rebrand:** Complete - homelab.yml -> octant.yml, /opt/homelab/ -> /opt/octant/
- **Volumes:** Dedicated `roles/volumes/` role with per-volume permissions; standalone `make deploy-volumes`
- **Destroy:** `make destroy-services` tears down all services in reverse dependency order
- **HAProxy:** Hypervisor load balancer proxying :443 (Traefik), :4646 (Nomad), :8500 (Consul), :9002 (Traefik dashboard) to all 3 VMs with active health checks; `make deploy-haproxy`
- **Container storage:** Dedicated 30G XFS disk (`/dev/vdc`) for Podman container storage via `roles/container-storage/`
- **Traefik ports:** HTTP (80), HTTPS (443), admin (9002) are static; metrics (8082) is dynamic
- **Metrics exporters:** node-exporter (port 9100), podman-exporter rootless (9883) and rootful (9882) on all nodes; Prometheus catch-all via `"metrics"` Consul tag
- **Grafana datasources:** Prometheus, Loki, and Tempo provisioned via `grafana-datasources.yml`; Node Exporter Full (1860) dashboard imported
- **Prometheus alerts:** All alerts resolving correctly (NodeExporterDown, DiskUsage, HighMemoryPressure, HighCpuUsage now functional); LokiDown resolved (was DNS issue in Alloy containers)
- **Direnv TF_VAR:** `.envrc` exports `TF_VAR_domain`, `TF_VAR_certresolver`, `TF_VAR_nomad`, `TF_VAR_consul` so direct `terraform apply` in module dirs uses correct values
- **Gatus:** 11 endpoints monitored across monitoring/infrastructure/apps groups
- **Uptime Kuma:** Running with MariaDB backend (db_uptimekuma in 1Password, Uptime Kuma 2.1.3)
- **Loki:** Ingesting journal logs from all 3 nodes via Alloy; labels: host, job, service_name
- **Homepage:** Working with HOMEPAGE_ALLOWED_HOSTS env var for host validation
- **Backups:** Restic daily at 02:00 (local CephFS repo), postgres-backup at 04:30, mariadb-backup at 04:00; Consul/Nomad snapshots included in restic job; results in Consul KV

---

## Ansible Patterns - Lessons Learned

### Variable Scoping

**Problem: Self-referential variables cause infinite recursion.**
```yaml
# BAD - if base_image_name is defined in group_vars, this recurses
vars:
  base_image_name: "{{ base_image_name | default('octant-base') }}"

# GOOD - let group_vars provide the value, or use a different local name
vars:
  _local_name: "{{ base_image_name | default('octant-base') }}"
```
*Fix: 632b161*

**Problem: Variables defined in one role's defaults aren't available in another role.**
```yaml
# vm_storage/defaults/main.yml defines vm_data_disk_format
# vm_provision/defaults/main.yml does NOT - but its template uses it

# GOOD - define shared variables in both role defaults or in group_vars
```
*Fix: fbb2539*

**Problem: `set_fact` in `include_role` loops operates on the play host, not the loop item.**
```yaml
# BAD - vm_ip_address gets overwritten each iteration, only last VM's IP survives
- name: Provision VM
  include_role: vm_provision
  vars:
    vm_name: "{{ item }}"
  loop: "{{ server_list }}"
# Inside vm_provision:
- set_fact:
    vm_ip_address: "{{ vm_ip.stdout }}"  # Overwrites on each loop iteration

# GOOD - accumulate into a dict
- set_fact:
    vm_ip_map: "{{ vm_ip_map | default({}) | combine({vm_name: vm_ip.stdout}) }}"
```
*Fix: f9cd910*

### Loop Variables

**Problem: Inner role loops using `item` collide with outer `include_role` loop.**
```yaml
# BAD - outer loop uses 'item', inner role loop also uses 'item'
- include_role:
    name: vm_provision
  loop: "{{ server_list }}"
# Inside role:
- set_fact:
    keys: "{{ keys + [lookup('file', item)] }}"
  loop: "{{ ssh_key_paths }}"  # 'item' collides!

# GOOD - use loop_control with distinct loop_var names
- include_role: ...
  loop: "{{ server_list }}"
  loop_control:
    loop_var: vm_host  # Outer loop
# Inside role:
  loop: "{{ ssh_key_paths }}"
  loop_control:
    loop_var: key_path  # Inner loop - no collision
```
*Fix: 17d79f2, a0cf2fd*

**Problem: Ansible `block` does not support `loop`.**
```yaml
# BAD - block with loop is silently broken
- block:
    - name: Destroy VM
      shell: virsh destroy {{ item }}
    - name: Undefine VM
      shell: virsh undefine {{ item }}
  loop: "{{ server_list }}"  # Does NOT work as expected

# GOOD - use individual tasks with loops
- name: Destroy VM {{ vm_host }}
  shell: virsh destroy {{ vm_host }}
  loop: "{{ server_list }}"
  loop_control:
    loop_var: vm_host

- name: Undefine VM {{ vm_host }}
  shell: virsh undefine {{ vm_host }}
  loop: "{{ server_list }}"
  loop_control:
    loop_var: vm_host
```
*Fix: a0cf2fd*

### Lookups and Filters

**Problem: `lookup('file', path, errors='ignore')` returns `None`, not empty string.**
```yaml
# BAD - None has no len()
when: lookup('file', path, errors='ignore') | length > 0

# BAD - default('') doesn't catch None in Ansible (only undefined)
when: lookup('file', path, errors='ignore') | default('') | length > 0

# BAD - default('', true) may still not work in all contexts
when: lookup('file', path, errors='ignore') | default('', true) | length > 0

# GOOD - avoid the problem entirely, use fileglob or stat
- set_fact:
    user_ssh_keys: >-
      [{% for path in key_paths %}
        {% if lookup('fileglob', path) %}"{{ lookup('file', path) }}"{% endif %}
      {% endfor %}]
```
*Fix: ffbd235, d7ece2c*

**Problem: `stat` runs on remote host, `lookup('file')` runs on controller.**
```yaml
# BAD - stat checks remote filesystem, lookup reads local filesystem
- stat:
    path: "{{ key_path }}"  # Checks on remote host
  register: result
- set_fact:
    key: "{{ lookup('file', result.key_path) }}"  # Reads from controller!

# GOOD - use lookup('env', 'HOME') and fileglob for controller-local operations
- set_fact:
    user_ssh_keys: >-
      [{% for path in [lookup('env', 'HOME') + '/.ssh/id_ed25519.pub'] %}
        {% if lookup('fileglob', path) %}"{{ lookup('file', path) }}"{% endif %}
      {% endfor %}]
```
*Fix: d7ece2c*

### Jinja2 Templates

**Problem: Inline Jinja2 conditionals in systemd unit files swallow newlines.**
```ini
# BAD - when condition is false, the line disappears and next line merges
Requires=network-online.target{% if tailscale %} tailscaled.service{% endif %}
After=network-online.target{% if tailscale %} tailscaled.service{% endif %}
Documentation=...
# Renders as: After=network-online.targetDocumentation=...

# GOOD - use block if/else to control entire lines
{% if tailscale_enabled | default(false) %}
Requires=network-online.target tailscaled.service
After=network-online.target tailscaled.service
{% else %}
Requires=network-online.target
After=network-online.target
{% endif %}
Documentation=...
```
*Fix: ca6cdd3*

**Problem: Jinja2 inline ternary may evaluate both branches.**
```yaml
# RISKY - Jinja2 may evaluate ansible_tailscale0 even when region == "home"
bind_addr = "{{ "0.0.0.0" if region == "home" else hostvars[host].ansible_tailscale0.ipv4.address }}"

# GOOD - use if/else block to prevent evaluation of undefined branch
{% if region == "home" %}
bind_addr = "0.0.0.0"
{% else %}
bind_addr = "{{ hostvars[host].ansible_tailscale0.ipv4.address }}"
{% endif %}
```
*Fix: 091a3dd*

### Role and Service Ordering

**Problem: `install-hashi` started the service before config was written.**
```yaml
# BAD - service starts with empty config dir, fails, systemd rate-limits restarts
# In install-hashi:
- systemd:
    name: "{{ name }}"
    state: started  # Config not written yet!

# Then in consul-server:
- template: consul-server.hcl  # Written AFTER install-hashi
- systemd:
    state: restarted  # Rate-limited by systemd!

# GOOD - install-hashi only enables and reloads daemon, calling role handles start
- systemd:
    name: "{{ name }}"
    enabled: true
    daemon_reload: true
    # No state: started
```
*Fix: 484d812*

**Problem: Service health check roles ran before the service was installed.**
```yaml
# BAD - configure-consul checked if consul-server was running
# before consul-server role had installed and configured it
- service:
    name: consul-server
    state: started
  until: ... ActiveState == "active"  # Fails - service doesn't exist yet

# GOOD - remove premature checks; consul keygen doesn't need the service running
```
*Fix: 5e23e80*

**Problem: Volumes at `/mnt/services` created before CephFS is mounted.**
```yaml
# BAD - creating dirs on root fs that get hidden by CephFS mount
# In consul-server role:
- file:
    path: "{{ item.path }}"  # /mnt/services/traefik/data etc.
  loop: "{{ volumes }}"
# Later, Ceph mounts /mnt/services, hiding these directories

# GOOD - create volume dirs AFTER Ceph is mounted (in 02-deploy-ceph.yml post_tasks)
```
*Fix: 202d0e1*

### Infrastructure Configuration

**Problem: Hardcoded interface names (`ansible_eth0`) don't work on all platforms.**
```yaml
# BAD - VMs use enp1s0 (virtio on q35), not eth0
bind_addr = "{{ ansible_eth0.ipv4.address }}"

# GOOD - use portable fact
bind_addr = "{{ ansible_default_ipv4.address }}"
```
*Fix: 475b4d3*

**Problem: TLS directory didn't exist when consul tried to create certs.**
```yaml
# GOOD - always ensure directory exists before using chdir
- file:
    path: "{{ configdirs['tls'] }}"
    state: directory
# Then:
- shell: consul tls ca create
  args:
    chdir: "{{ configdirs['tls'] }}"
```
*Fix: 202d0e1*

**Problem: TLS cert permissions blocked non-root agents.**
```yaml
# consul tls cert create generates keys with 0600 owned by root
# consul-agent runs as hashi user - can't read the keys

# GOOD - set group ownership and permissions after cert generation
- file:
    path: "{{ configdirs['tls'] }}"
    group: "{{ group }}"  # hashi
    mode: "0750"
    recurse: true
- shell: chmod 640 {{ configdirs['tls'] }}/*-key.pem
```
*Fix: bd9173e*

**Problem: Only one client cert generated, but two needed (agent + agent-root).**
```yaml
# BAD - consul-agent uses client-consul-0, consul-agent-root uses client-consul-1
consul tls cert create -client -dc octant  # Only creates -0

# GOOD - generate two client certs
consul tls cert create -client -dc octant &&
consul tls cert create -client -dc octant  # Creates both -0 and -1
```
*Fix: f0a29bd*

**Problem: Gossip keys generated independently on each node.**
```yaml
# BAD - each node gets a different gossip key
- command: consul keygen
  register: consul_gossip_key_output
# All 3 nodes generate different keys - cluster can't communicate

# GOOD - use run_once so all nodes share the same key
- command: consul keygen
  register: consul_gossip_key_output
  run_once: true
- set_fact:
    consul_gossip_key: "{{ consul_gossip_key_output.stdout }}"
  # set_fact without run_once distributes to all hosts
```
*Fix: 7795e43*

### Ansible Configuration

**Problem: Playbooks in subdirectory can't find roles at repo root.**
```
# roles/ is at repo root, playbooks/ is a subdirectory
# Ansible looks for roles relative to the playbook location

# GOOD - create ansible.cfg at repo root
[defaults]
roles_path = roles
```
*Fix: 34cc047*

**Problem: Multiple inventory files needed for different playbook phases.**
```makefile
# provision-vms needs both hypervisors.yml (where to create VMs)
# and groups.yml (which VMs to create, with vm_mac/vm_ip)
VM_INVENTORY := -i inventory/hypervisors.yml -i inventory/groups.yml

# cluster deploy needs provisioned_vms.yml (connection details)
# and groups.yml (volumes list, other group vars)
VM_CLUSTER_INVENTORY := -i inventory/provisioned_vms.yml -i inventory/groups.yml
```
*Fix: a7e8c01, fd640ba*

### Cloud-Init

**Problem: `groups: users, admin, sudo` fails when username matches a group.**
```yaml
# BAD - useradd exit code 9: group 'admin' conflicts with user 'admin'
users:
  - name: admin
    groups: users, admin, sudo

# GOOD - don't include the username as a supplementary group
users:
  - name: admin
    groups: users, sudo
```
*Fix: 2d68ac6*

**Problem: `chpasswd` uses deprecated `list:` format.**
```yaml
# DEPRECATED (works on Debian 12 but older format)
chpasswd:
  list: |
    admin:password
  expire: false

# PREFERRED (cloud-init 22.2+)
chpasswd:
  users:
    - name: admin
      password: password
      type: text
  expire: false
```
*Noted but not yet fixed - works for now.*

### TLS Configuration

**Problem: Nomad TLS enabled but no cert generation exists.**
```yaml
# BAD - nomad.tls_enabled: true but no role generates Nomad TLS certs
# consul-server role generates Consul certs only
# Nomad templates reference non-existent files:
#   /opt/octant/config/tls/home-server-nomad.pem

# GOOD - disable Nomad TLS for initial deployment (private libvirt network)
# Also: wrap entire tls {} block in conditional, not just its contents
{% if (nomad.tls_enabled | default('', false)) %}
tls {
  ...
}
{% endif %}
# Instead of rendering empty tls {} block
```

**Problem: Missing closing quote in HCL template non-TLS path.**
```hcl
# BAD - missing closing quote (in all 3 nomad templates)
grpc_address = "127.0.0.1:{{ consul.ports.grpc }}
ssl = false

# GOOD
grpc_address = "127.0.0.1:{{ consul.ports.grpc }}"
ssl = false
```

### Permissions and Directories

**Problem: Nomad 1.11 `alloc_mounts` dir created at parent of data_dir.**
```yaml
# BAD - nomad-agent runs as hashi, data_dir is /opt/octant/data/nomad-agent
# Nomad tries to create /opt/octant/data/alloc_mounts
# but /opt/octant/data is owned by root:root 755

# GOOD - pre-create the directory before starting nomad-agent
- file:
    path: "{{ datadir }}/alloc_mounts"
    state: directory
    owner: "{{ user }}"
    group: "{{ group }}"
```

**Problem: nomad-agent-root wait_for checked wrong port.**
```yaml
# BAD - nomad-agent-root waited on agent port instead of root_agent port
port: "{{ nomad.ports.agent_http }}"      # 5646

# GOOD
port: "{{ nomad.ports.root_agent_http }}"  # 6646
```

### Package Dependencies

**Problem: Debian 12 cloud image doesn't include cron.**
```yaml
# BAD - restic role uses ansible.builtin.cron but crontab not installed
- cron:
    name: "Restic backup"
    ...
# fatal: Failed to find required executable "crontab"

# GOOD - install cron alongside restic
- apt:
    name:
      - restic
      - cron
```

### Variable References

**Problem: Template references undefined port variable.**
```yaml
# BAD - nomad config doesn't define ports.https
NOMAD_ADDR: "https://...:{{ nomad.ports.https }}"

# GOOD - use the port that's actually defined
NOMAD_ADDR: "http://localhost:{{ nomad.ports.http }}"
```
*Fix: ba6ac1a*

---

## Bugs Fixed During Testing (Chronological)

| Commit | Category | Issue |
|--------|----------|-------|
| 632b161 | Variables | Self-referential vars in 00-build-base-image.yml |
| a7e8c01 | Makefile | Missing groups.yml from provision-vms target |
| 34cc047 | Config | Missing ansible.cfg (roles_path) |
| f7510c8 | Storage | Pool conflict, cloud-init staleness, SSH key accumulation |
| 17d79f2 | Loops | Loop variable collision (`item`) |
| ffbd235 | Lookups | NoneType from lookup('file', errors='ignore') |
| fbb2539 | Variables | Missing vm_data_disk_format in vm_provision |
| d7ece2c | Lookups | Remote stat vs local lookup mismatch |
| 2d68ac6 | Cloud-Init | User creation fail ('admin' group conflict) |
| a0cf2fd | Loops | block+loop unsupported, loop_var consistency |
| c3fea47 | Makefile | Double -i flags |
| 661455d | Feature | DHCP reservations with fixed MACs |
| 7eaf2b9 | Feature | Secrets generation script |
| a21cbb2 | Feature | Tailscale conditional |
| 5e23e80 | Ordering | Premature service checks in configure-consul/nomad |
| 7795e43 | Secrets | Gossip key per-node instead of shared; TLS path fix |
| fd640ba | Makefile | Missing groups.yml in cluster inventory |
| 202d0e1 | Ordering | TLS dir creation; volume creation before Ceph |
| 475b4d3 | Templates | ansible_eth0 → ansible_default_ipv4 |
| b6f975d | Templates | tailscaled systemd hard dependency |
| ca6cdd3 | Templates | Jinja2 newline swallowing in service files |
| 484d812 | Ordering | install-hashi starting service before config |
| 091a3dd | Templates | Tailscale conditionals across all roles |
| c7711b0 | Feature | Auto-approve teardown flag |
| bd9173e | Permissions | TLS cert permissions for non-root agents |
| f0a29bd | TLS | Missing second client cert for agent-root |
| ba6ac1a | Variables | nomad.ports.https undefined |
| pending | TLS | Nomad TLS enabled with no certs; disabled for initial deploy |
| pending | Templates | Missing closing quote in HCL grpc_address (3 templates) |
| pending | Permissions | Nomad 1.11 alloc_mounts dir permission denied for hashi user |
| pending | Ports | nomad-agent-root wait_for checked wrong port (5646 vs 6646) |
| pending | Packages | Debian 12 cloud image missing cron for restic role |

## App Migration Status (feature/app-migration branch)

### Completed

- **Rebrand:** homelab.yml -> octant.yml, /opt/homelab/ -> /opt/octant/, all docs updated
- **DNS tiers:** sslip.io default + Cloudflare opt-in documented; configured for lab.shamsway.net
- **1Password seeding:** seed-onepassword role creates missing credentials automatically
- **Vault clearing:** scripts/clear-vault-secrets.sh for clean rebuild testing
- **Terraform modules:** 25 apps migrated from octant-private (20 core + 5 optional)
- **Execution order:** Full terraform_execution_order with core/observability/LLM/optional tiers
- **Volumes:** Dedicated `roles/volumes/` with per-volume permissions; standalone `05-deploy-volumes.yml` playbook; integrated into Ceph deploy
- **Health checks:** Consul service registration and Nomad job listing added

### Core Apps Deployed (terraform apply succeeded)

traefik, postgres, mariadb, nginx, mqtt, excalidraw, qdrant, searxng, uptimekuma, pgadmin, homepage, prometheus, loki, tempo, alertmanager, alloy, grafana, gatus

### Optional Apps (commented out, require manual 1Password items)

litellm, n8n, open-webui, phoenix, openclaw-gateway, ntfy

### Bugs Fixed During App Migration

| Commit | Category | Issue |
|--------|----------|-------|
| fa5983d | Environment | OP_SERVICE_ACCOUNT_TOKEN not inherited by Ansible command module |
| 46466d3 | CLI syntax | op item create uses assignment syntax (username=val) not flags (--username) |
| 16a8fd6 | CLI stdin | op CLI interprets empty stdin as piped JSON; redirect from /dev/null |
| multiple | Variables | Missing consul/domain/certresolver variable declarations in 18 modules |
| a61d0da | Volumes | mariadb used host volume not registered in Nomad; switched to bind mount |
| 7319f93 | Nomad | searxng multi-task group needs explicit task field for Consul Connect |
| pending | Volumes | Ported volumes role from octant-private with per-volume permission overrides |
| pending | Typo | Fixed weaviate path typo (weviate -> weaviate) in inventory and terraform |
| pending | Permissions | Added mode 0700 for postgres-data volume |
| pending | Auth | Removed placeholder auth.json from podman-rootless (caused "illegal base64" pull failures) |
| pending | Env | Nomad TLS env vars conditional on nomad.tls_enabled; fixed cli→client cert filename |
| pending | Health | Health check Consul service queries now retry with backoff (12x10s) |
| pending | Deploy | Moved litellm to optional tier (requires manual 1Password API keys) |
| pending | Metrics | Added node-exporter and podman-exporter roles; Prometheus catch-all for "metrics" tag |
| pending | Makefile | Fixed deploy-role/deploy-host/deploy-role-host to use VM_CLUSTER_INVENTORY |
| pending | Terraform | Added TF_VAR_ exports to .envrc so direct terraform apply uses correct domain/certresolver |

### Remaining Work

1. ~~Full `make rebuild-clean` validation~~ → DONE: rebuild with HAProxy + DNS + HTTPS verified
2. ~~Templatize `traefik.toml`~~ → DONE
3. ~~Create `terraform/dns-lab/`~~ → DONE
4. ~~Test Cloudflare DNS-01 certificate generation~~ → DONE (12 certs issued)
5. ~~Cloudflare creds from 1Password~~ → DONE (switched from .env passthrough to 1Password Terraform provider)
6. ~~Verify Nomad jobs reach "running"~~ → DONE: litellm fixed (host volume hiding entrypoint), DNS fixed (containers now use VM IPs for .consul resolution)
7. ~~Enable optional apps~~ → DONE: litellm, n8n, phoenix deployed and running; open-webui ready (needs litellm); created postgres databases for all three
8. Remove legacy host volume mounts from remaining Nomad job specs (audit all *.nomad.hcl for volume/volume_mount blocks)
9. Fix SSH known_hosts management (add host keys after VM deploy, remove on teardown)
10. Squash/clean commit history before merge
11. Implement Docker Hub credentials via 1Password
12. Reorganize repo structure to avoid conflicts with main branch bare-metal deployment (see design session notes)
13. ~~Uptime Kuma: Create MariaDB user/database secrets (1Password) and configure Uptime Kuma to use MariaDB~~ → DONE: db_uptimekuma in 1Password, MariaDB database/user created, Nomad job updated with UPTIME_KUMA_DB_* env vars
14. ~~Backups: Update restic backup job~~ → DONE: restic with local CephFS repo, Consul/Nomad snapshots, postgres-backup and mariadb-backup jobs deployed. Phase 2: deploy MinIO for S3-compatible target, set up hypervisor cron for offsite copy
15. ~~Logging: Fix Loki log ingestion~~ → DONE: Root cause was incorrect DNS in Alloy/Tempo/Uptime Kuma containers (using libvirt gateway 192.168.122.1 instead of Consul DNS). Redeployed affected services. All 3 nodes shipping journal logs to Loki.
16. ~~Homepage: Fix "Host validation failed" error~~ → DONE: Added HOMEPAGE_ALLOWED_HOSTS env var to Nomad job spec
