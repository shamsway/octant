# Cluster Remediation Plan — 2026-03-11

## Current Issue

All three VMs (octant-01/02/03) have kernel RBD (RADOS Block Device) processes stuck in D-state (uninterruptible sleep). The kernel ceph client (`libceph`) cannot connect to Ceph monitors/OSDs — it reports `-101` (ENETUNREACH) on msgr v1 connections continuously in `dmesg`. Userspace ceph tools work fine, but the kernel's RBD block device I/O is frozen.

### Symptoms

- `jbd2/rbd*` kernel threads in D-state on all nodes (ext4 journal threads for CSI-mounted RBD volumes)
- Cascading D-state in `mount`, `umount`, `vgs`, `lvs`, and container `find`/`chown` processes
- Load average ~27 on octant-01 (7 RBD devices mapped)
- Postgres crashed ("unexpected postmaster exit") — I/O stalled on its RBD volume
- Loki and Qdrant stuck in `pending` — CSI can't stage their volumes
- Ansible `gather_facts` hangs because `vgs` (hardware subset) blocks on stuck `/dev/rbd*` devices
- CephFS was not mounted on octant-02 and octant-03 (manually remounted during investigation)

### Root Cause

**CSI node plugin Docker bridge networking.** The `ceph-csi-node` Nomad job ran its privileged container with Docker's default `bridge` network mode. When the CSI plugin executed `rbd map` inside this container, the kernel RBD module inherited the container's bridge network namespace. From this namespace, the kernel ceph client (`libceph`) could not reach the Ceph monitors and OSDs at `192.168.122.x` — producing continuous `-101` (ENETUNREACH) errors on msgr v1 connections. Userspace tools (running in the host namespace) worked fine, which made the issue appear to be a kernel-level ceph bug rather than a networking problem.

D-state processes result from blocked I/O on the stuck RBD devices and cannot be killed — only a VM reboot clears them.

## Steps Already Taken (this session)

All changes are on branch `feature/app-migration` in the `.worktrees/vm-deployment` worktree.

### 1. Cluster start playbook improvements (`playbooks/10-cluster-start.yml`)
- Added "Prune Container Images" phase — runs `podman system prune -a -f` (hashi user) and `docker system prune -a -f` (root) on all nodes after SSH validation
- Added CSI health check gate — waits up to 120s for `nomad plugin status ceph-csi` to show 3 healthy nodes before declaring cluster ready
- Updated phase list in header comments and cluster start summary message

### 2. Shutdown playbook `virsh destroy` fallback (`playbooks/08-graceful-shutdown.yml`)
- VM shutdown phase now attempts graceful `virsh shutdown` with 120s timeout
- Automatically runs `virsh destroy` on any VMs that don't shut down within the timeout
- Reports forced VMs in shutdown summary with D-state warning

### 3. HAProxy wall broadcast fix
- **Root cause found**: `systemd-journald` has `ForwardToWall=yes` by default with `MaxLevelWall=emerg`. HAProxy logs "backend X has no server available!" at syslog emerg level (priority 0). Journald forwards these to all terminals via wall, completely bypassing the rsyslog `& stop` rule in `49-haproxy.conf`.
- **Fix**: New journald drop-in template `roles/haproxy/templates/no-wall-broadcasts.conf.j2` sets `ForwardToWall=no`
- Updated `roles/haproxy/tasks/main.yml` to deploy the drop-in and notify `restart journald` handler
- Added `restart journald` handler to `playbooks/02.5-deploy-haproxy.yml`
- Updated rsyslog template comment to be accurate
- **Already deployed** via `make deploy-haproxy`

### 4. Ansible `gather_facts` hang fix
- `playbooks/04-health-check.yml`: changed to `gather_facts: false` (no facts needed)
- `playbooks/podman-cleanup.yml`: changed to `gather_facts: false` (no facts needed)
- `playbooks/02-deploy-ceph.yml`: added `module_defaults` with `gather_subset: !hardware`
- `playbooks/07-capture-state.yml`: added `gather_subset: !hardware`, replaced `ansible_memtotal_mb` and `ansible_processor_vcpus` with shell commands reading `/proc/meminfo` and `nproc`

### 5. Systemd dependency chain templates (NOT YET DEPLOYED)
Updated service templates in `roles/install-hashi/templates/`:
- `consul-server.service.j2`: added `Wants=ceph.target` and `After=ceph.target`
- `consul-agent.service.j2`: added `Wants=consul-server.service` and `After=consul-server.service`
- `consul-agent-root.service.j2`: added `Wants=consul-server.service` and `After=consul-server.service`
- `nomad-agent.service.j2`: added `consul-agent.service` to `Wants` and `After` (alongside existing `nomad-server.service`)
- `nomad-agent-root.service.j2`: added `consul-agent-root.service` to `Wants` and `After` (alongside existing `nomad-server.service`)
- `nomad-server.service.j2`: unchanged (already has `Requires=consul-server.service` and `After=consul-server.service`)

Resulting boot order: `ceph.target → consul-server → consul-agent(s) → nomad-server → nomad-agent(s)`

## Remediation Plan (execute in order)

### Phase 1: Stop all services on all VMs

On each VM (octant-01, octant-02, octant-03), stop services in reverse dependency order. Use `ansible` ad-hoc commands or SSH. Services may hang due to D-state — use timeouts.

```bash
# Stop Nomad agents and server
ssh admin@192.168.122.101 'sudo systemctl stop nomad-agent nomad-agent-root nomad-server'
ssh admin@192.168.122.102 'sudo systemctl stop nomad-agent nomad-agent-root nomad-server'
ssh admin@192.168.122.103 'sudo systemctl stop nomad-agent nomad-agent-root nomad-server'

# Stop Consul agents and server
ssh admin@192.168.122.101 'sudo systemctl stop consul-agent consul-agent-root consul-server'
ssh admin@192.168.122.102 'sudo systemctl stop consul-agent consul-agent-root consul-server'
ssh admin@192.168.122.103 'sudo systemctl stop consul-agent consul-agent-root consul-server'

# Stop Podman and Docker (may hang due to D-state containers)
ssh admin@192.168.122.101 'sudo systemctl stop podman docker'
ssh admin@192.168.122.102 'sudo systemctl stop podman docker'
ssh admin@192.168.122.103 'sudo systemctl stop podman docker'
```

**Note**: Some `systemctl stop` commands may hang due to D-state processes. If they don't complete within 30 seconds, proceed to Phase 2 — the reboot will clear everything.

### Phase 2: Reboot all VMs

Use `virsh destroy` (not `virsh shutdown`) because `virsh shutdown` may hang on D-state processes:

```bash
sudo virsh destroy octant-01 && sudo virsh destroy octant-02 && sudo virsh destroy octant-03
# Wait a moment, then start
sudo virsh start octant-01 && sudo virsh start octant-02 && sudo virsh start octant-03
```

Wait for SSH connectivity:
```bash
for h in 192.168.122.101 192.168.122.102 192.168.122.103; do
  until ssh -o ConnectTimeout=3 admin@$h echo ok 2>/dev/null; do sleep 3; done
  echo "$h ready"
done
```

### Phase 3: Verify clean boot (no D-state)

```bash
for h in 101 102 103; do
  echo "--- octant-$(printf '%02d' $((h-100))) ---"
  ssh admin@192.168.122.$h 'ps aux | grep -c " D[+ ]"'
done
```

Should show 0 (or near-0) D-state processes on each node.

### Phase 4: Deploy systemd dependency changes

Run the install-hashi role to push updated service files with Ceph dependency chain:

```bash
make deploy-role ROLE=install-hashi
```

This will:
- Template and deploy all 6 service files (consul-server, consul-agent, consul-agent-root, nomad-server, nomad-agent, nomad-agent-root)
- Run `systemctl daemon-reload` on each node

### Phase 5: Verify systemd dependencies

```bash
ssh admin@192.168.122.101 'systemctl show consul-server.service -p Wants,After | grep ceph'
ssh admin@192.168.122.101 'systemctl show consul-agent.service -p Wants,After | grep consul-server'
ssh admin@192.168.122.101 'systemctl show nomad-agent.service -p Wants,After | grep consul-agent'
```

### Phase 6: Verify Ceph health and CephFS

```bash
ssh admin@192.168.122.101 'sudo ceph health; sudo ceph osd dump | head -3'
for h in 101 102 103; do
  ssh admin@192.168.122.$h 'mountpoint -q /mnt/services && echo "CephFS: mounted" || echo "CephFS: NOT mounted"'
done
```

If CephFS is not mounted, mount it: `ssh admin@192.168.122.X 'sudo mount /mnt/services'`

If Ceph OSD flags are still set from shutdown: `ssh admin@192.168.122.101 'sudo ceph osd unset noout && sudo ceph osd unset nobackfill && sudo ceph osd unset norecover'`

### Phase 7: Start cluster services

Use the cluster start playbook (which now includes container prune and CSI health gate):

```bash
make start ARGS="-e unset_ceph_flags=yes"
```

Or start manually in dependency order:
```bash
# Services should auto-start via systemd after reboot, but if not:
for h in 101 102 103; do
  ssh admin@192.168.122.$h 'sudo systemctl start consul-server && sudo systemctl start consul-agent consul-agent-root && sudo systemctl start nomad-server && sudo systemctl start nomad-agent nomad-agent-root'
done
```

### Phase 8: Deploy services

```bash
make deploy-services
```

### Phase 9: Health check

```bash
make health-check
```

Verify:
- All Consul members alive (9: 3 servers + 6 agents)
- All Nomad nodes ready (6: 3 rootless + 3 root)
- Ceph HEALTH_OK
- CephFS mounted on all nodes
- CSI plugin healthy (3/3 nodes)
- Postgres, MariaDB, Traefik registered in Consul
- No D-state processes

## Fixes Applied During Remediation

### 6. CSI node plugin `network_mode = "host"` (ROOT CAUSE FIX)

Added `network_mode = "host"` to `terraform/ceph-csi/ceph-csi-node.nomad.hcl`. Without this, the CSI container ran on Docker bridge networking and `rbd map` caused the kernel ceph client to use the container's network namespace, making Ceph mons/OSDs unreachable.

### 7. Docker `allow_privileged` config conflict

Added `allow_privileged = true` to the `plugin "docker"` block in `roles/nomad-agent-root/templates/nomad-agent-root.hcl.j2`. The main agent config's `plugin "docker"` block was overriding the separate `docker.hcl` file (created by the docker role) that had this setting, causing CSI node containers to fail with "Docker privileged mode is disabled on this Nomad agent."

### 8. `ansible_uptime_seconds` fix in capture-state

Replaced `ansible_uptime_seconds` (not available with `gather_subset: !hardware`) with a shell command reading `/proc/uptime` in `playbooks/07-capture-state.yml`.

### 9. Startup playbook: CephFS mount + D-state check

Updated `playbooks/10-cluster-start.yml`:
- CephFS check now mounts `/mnt/services` if not already mounted (previously only checked)
- Added D-state process check after boot validation with warning message

### 10. Duplicate `plugin "docker"` blocks causing mass container kills

**Symptom**: Every ~10 minutes, ALL Docker containers on ALL 3 nodes were SIGKILL'd (exit 137). Nomad logs showed `"removal of container ... is already in progress"`. Affected services: postgres, loki, prometheus, qdrant, neo4j, mongodb, mariadb, ceph-csi-node.

**Cascade effects**:
- Services with `restart.mode = "fail"` and low restart attempts (e.g., loki at 2 attempts/30m) permanently failed
- CSI node plugin killed → RBD volumes briefly unavailable → services with CSI volumes couldn't restart
- Neo4j deregistering from Consul caused Graphiti's template (`{{ range service "neo4j" }}`) to re-render empty, removing `NEO4J_URI` env var → Pydantic validation error → permanent failure
- Postgres crash-recovered each time but eventually exhausted restart attempts

**Root cause**: Both `docker.hcl` and `nomad-agent-root.hcl` in `/opt/octant/config/nomad-agent-root.d/` contained a `plugin "docker"` block. Despite both having `dangling_containers { enabled = false }`, Nomad's HCL config merging of duplicate plugin blocks is unreliable. The dangling container GC was still firing.

**Fix**: Removed `docker.hcl` entirely. All Docker plugin configuration now lives solely in `nomad-agent-root.hcl.j2`. Updated `roles/docker/tasks/main.yml` to remove the file (instead of creating it). Restarted `nomad-agent-root` on all 3 nodes. Kills stopped immediately.

**Key lesson**: NEVER define the same Nomad plugin in multiple HCL files in the same config directory. Nomad's config merging for duplicate plugin blocks is broken — settings can be silently ignored or reverted to defaults.

### 11. Rootless agent Docker GC killing root-agent containers

**Symptom**: After fixing the duplicate `plugin "docker"` block (section 10), Docker containers managed by `nomad-agent-root` were still being SIGKILL'd every ~9m44s (584 seconds). This affected ALL Docker containers (CSI nodes, CSI controller, any Docker-driver service). Containers managed by Podman (rootless agent workloads) were unaffected. A non-Nomad Docker container (`docker run alpine sleep 3600`) survived indefinitely, confirming Nomad was the killer.

**Debugging journey**:
- Verified `docker.hcl` removed, `dangling_containers { enabled = false }` in nomad-agent-root.hcl ✓
- Set `gc { container = false }` — kills continued
- Changed template `change_mode = "restart"` to `"noop"` — kills continued
- Removed `restart` stanza entirely — kills continued
- Checked OOM (only 21 MiB / 256 MiB used), kernel dmesg, Docker daemon config — all clean
- Docker events showed `execDuration=584` (9.73 min) consistently, `signal=9` (SIGKILL)
- All 3 nodes killed within 1 second of each other — coordinated server-side decision

**Root cause**: The **rootless** `nomad-agent` (not `nomad-agent-root`) was auto-detecting the Docker socket and enabling the Docker driver. Its dangling container GC scanned Docker for containers, found CSI and other Docker-driver containers launched by `nomad-agent-root`, and removed them as "untracked" — because the rootless agent has no knowledge of the root agent's allocations. The GC `period` default of `"5m"` plus `creation_grace` of `"5m"` = ~10 minute kill cycle.

The rootless agent log line that confirmed it:
```
client.driver_mgr.docker: removed untracked container: driver=docker container_id=065059a6
```

This likely started when Docker was installed on all nodes for CSI support. Before that, the rootless agents had no Docker socket to discover, so the driver was never auto-detected.

**Fix**: Added an explicit `plugin "docker"` block to `roles/nomad-agent/templates/nomad-agent.hcl.j2` that disables all Docker GC on rootless agents:
```hcl
plugin "docker" {
  config {
    gc {
      image     = false
      container = false
      dangling_containers {
        enabled = false
      }
    }
  }
}
```

Also reverted `gc { container = false }` to `container = true` in nomad-agent-root (the root agent's GC is fine — it tracks its own containers correctly).

**Key lesson**: When running paired Nomad agents (rootless + root) on the same host sharing a Docker socket, the rootless agent MUST have Docker GC disabled. Otherwise it treats root-agent containers as "untracked" and removes them. Nomad auto-detects Docker if the socket is accessible — explicit configuration is required to prevent cross-agent GC contamination.

**Additional changes during investigation** (can be reverted if desired):
- CSI jobs: removed `restart` stanza, changed `change_mode` to `"noop"` (harmless, keeps CSI more stable)
- nomad-agent-root.hcl: `gc { container = false }` (should revert to `true` now that root cause is fixed)

## Post-Remediation Status (2026-03-11, evening session)

- **D-state**: 0 processes on all 3 nodes
- **Ceph**: HEALTH_OK, 3 OSDs up, 193 PGs active+clean
- **Consul**: 9/9 members alive
- **Nomad**: 6/6 nodes ready, all eligible
- **CSI**: Controllers 1/1, Nodes 3/3 healthy
- **Docker GC**: Mass kills stopped after removing duplicate plugin "docker" block
- **Running services**: ~36 services running, including all databases (postgres, mariadb, mongodb-1/2/3, neo4j, qdrant, redis)
- **Still stopped** (need terraform taint + apply): litellm, linkding, linkwarden, minio, n8n, openclaw-gateway, uptimekuma, falkordb, aippt, nginx
- **MongoDB**: rs0 replica set healthy — PRIMARY on mongodb-2, SECONDARYs on mongodb-1/3

## Key Files Modified

- `playbooks/10-cluster-start.yml` — container prune, CSI health gate, CephFS mount, D-state check
- `playbooks/08-graceful-shutdown.yml` — virsh destroy fallback
- `playbooks/04-health-check.yml` — gather_facts: false
- `playbooks/podman-cleanup.yml` — gather_facts: false
- `playbooks/02-deploy-ceph.yml` — gather_subset: !hardware
- `playbooks/07-capture-state.yml` — gather_subset: !hardware + /proc-based hw facts (including uptime)
- `playbooks/02.5-deploy-haproxy.yml` — restart journald handler
- `roles/haproxy/tasks/main.yml` — journald drop-in deployment
- `roles/haproxy/templates/no-wall-broadcasts.conf.j2` — new file
- `roles/haproxy/templates/49-haproxy.conf.j2` — updated comment
- `roles/install-hashi/templates/consul-server.service.j2` — After=ceph.target
- `roles/install-hashi/templates/consul-agent.service.j2` — After=consul-server.service
- `roles/install-hashi/templates/consul-agent-root.service.j2` — After=consul-server.service
- `roles/install-hashi/templates/nomad-agent.service.j2` — After=consul-agent.service
- `roles/install-hashi/templates/nomad-agent-root.service.j2` — After=consul-agent-root.service
- `roles/nomad-agent-root/templates/nomad-agent-root.hcl.j2` — `allow_privileged = true` + dangling GC disabled in docker plugin
- `roles/docker/tasks/main.yml` — changed from creating `docker.hcl` to removing it (eliminates duplicate plugin block)
- `terraform/ceph-csi/ceph-csi-node.nomad.hcl` — `network_mode = "host"`
