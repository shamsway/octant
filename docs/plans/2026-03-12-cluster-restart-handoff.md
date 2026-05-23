# Cluster Restart Handoff — 2026-03-12

## Context

We've been debugging a cluster-wide container kill bug for several hours. The cluster VMs are running but most services are stopped. Use this prompt to continue the recovery.

## What Happened

1. **Original incident (2026-03-11)**: Docker containers on root agents were being SIGKILL'd every ~10 minutes. Initial fix removed a duplicate `plugin "docker"` block from `docker.hcl` (see `docs/plans/2026-03-11-cluster-remediation.md`, section 10).

2. **The real root cause (section 11 of remediation doc)**: The **rootless** `nomad-agent` auto-detected the shared Docker socket and ran its own dangling container GC. Since it doesn't track containers launched by `nomad-agent-root`, it killed them all as "untracked" every ~10 minutes. Log signature: `client.driver_mgr.docker: removed untracked container` from `nomad-agent` (NOT `nomad-agent-root`).

3. **The fix**: Added an explicit `plugin "docker"` block to `roles/nomad-agent/templates/nomad-agent.hcl.j2` that disables Docker GC on rootless agents. This was also applied live to all 3 nodes at `/opt/octant/config/nomad-agent.d/nomad-agent.hcl`. The live files were created via `sed` and had a formatting issue (stray `n` character) which was fixed with a python one-liner. **The Ansible template is correct but the live configs should be validated against it.**

## Current State (2026-03-12, ~02:20 UTC)

### Infrastructure
- **VMs**: All 3 up (octant-01/02/03)
- **Ceph**: HEALTH_OK, 3/3 OSDs up, flags cleared
- **CephFS**: Mounted on all 3 nodes at `/mnt/services`
- **Consul**: 9/9 members alive (3 servers + 6 clients)
- **Nomad**: 6/6 nodes ready and eligible
- **CSI**: Controllers 1/1, Nodes 3/3 healthy — **CSI containers survived past 10 minutes** (fix confirmed)
- **Docker**: Active on all nodes, no container kills

### Running Services
- ceph-csi-controller, ceph-csi-node (CSI infrastructure)
- traefik (was stalled due to nomad-agent crash-loop from bad config, should restart now)
- postgres (started by user)

### Stopped Services (need `terraform taint` + `terraform apply`)
- litellm, uptimekuma, linkding, n8n, minio, linkwarden, falkordb, openclaw-gateway
- mariadb, mongodb-1/2/3, neo4j, qdrant, redis (databases)
- All other application services (grafana, prometheus, loki, alertmanager, etc.)
- Skip: aippt, nginx (pre-existing issues)

## Tasks for Next Session

### 1. Validate configs are correct on all nodes
```bash
# Verify rootless agent has docker GC disabled (no stray characters)
for h in 101 102 103; do
  echo "=== octant-$(printf '%02d' $((h-100))) ==="
  ssh admin@192.168.122.$h 'grep -A12 "plugin \"docker\"" /opt/octant/config/nomad-agent.d/nomad-agent.hcl'
done

# Verify root agent has docker.hcl removed and proper config
for h in 101 102 103; do
  echo "=== octant-$(printf '%02d' $((h-100))) ==="
  ssh admin@192.168.122.$h 'ls /opt/octant/config/nomad-agent-root.d/docker.hcl 2>&1; grep -A12 "plugin \"docker\"" /opt/octant/config/nomad-agent-root.d/nomad-agent-root.hcl'
done
```

### 2. Validate all Consul/Nomad components
```bash
ssh admin@192.168.122.101 'consul members'
ssh admin@192.168.122.101 'nomad node status -short'
ssh admin@192.168.122.101 'nomad plugin status ceph-csi'
ssh admin@192.168.122.101 'nomad job status -short'
```

### 3. Ensure Ansible roles are correct
- `roles/nomad-agent/templates/nomad-agent.hcl.j2` — must have `plugin "docker"` with GC disabled
- `roles/nomad-agent-root/templates/nomad-agent-root.hcl.j2` — `gc { container = false }` was set during debugging; consider reverting to `container = true` now that the real fix is in place
- `roles/docker/tasks/main.yml` — must remove `docker.hcl` (not create it)

### 4. Verify CSI stability (no kills for 15+ minutes)
```bash
# Watch for container kills
ssh admin@192.168.122.101 'sudo docker events --since "15 min ago" | grep "container kill"'
# Check CSI uptime
ssh admin@192.168.122.101 'nomad plugin status ceph-csi'
```

### 5. Start databases (one at a time, verify each before next)
Order: mariadb → redis → mongodb-1/2/3 → neo4j → qdrant
```bash
cd terraform/<service>
terraform taint nomad_job.<resource_name>
terraform apply -auto-approve
# Verify: ssh admin@192.168.122.101 'nomad job status <service>'
```
Note: postgres is already running.

### 6. Start application services
Order (least risk first): litellm → uptimekuma → linkding → n8n → minio → linkwarden → falkordb → openclaw-gateway

Then remaining services: grafana, prometheus, loki, alertmanager, alloy, tempo, gatus, etc.

### 7. Verify no container kills after all services deployed
```bash
for h in 101 102 103; do
  ssh admin@192.168.122.$h 'sudo docker events --since "15 min ago" | grep "container kill" | wc -l'
done
```

## Key Files Modified This Session
- `roles/nomad-agent/templates/nomad-agent.hcl.j2` — added `plugin "docker"` with GC disabled
- `roles/nomad-agent-root/templates/nomad-agent-root.hcl.j2` — changed `gc { container = false }` (may revert)
- `terraform/ceph-csi/ceph-csi-node.nomad.hcl` — removed `restart` stanza, changed `change_mode = "noop"`
- `terraform/ceph-csi/ceph-csi-controller.nomad.hcl` — removed `restart` stanza, changed `change_mode = "noop"`
- `docs/plans/2026-03-11-cluster-remediation.md` — added section 11 documenting root cause

## Monitoring Commands
```bash
# Container kills (the canary)
ssh admin@192.168.122.101 'sudo docker events --since "5 min ago" | grep "container kill"'
# CSI health
ssh admin@192.168.122.101 'nomad plugin status ceph-csi'
# Job status summary
ssh admin@192.168.122.101 'nomad job status -short | grep -v "dead (stopped)"'
# Ceph
ssh admin@192.168.122.101 'sudo ceph health'
```
