# Post-Mortem: Cluster Restart Issues (2026-03-11)

## Timeline

- **01:34 UTC** — Graceful shutdown completed (`make shutdown`), VMs shut down, snapshots taken
- **03:07 UTC** — VMs started (`make start`), cluster boot begins
- **03:26 UTC** — `make deploy-services` runs, services begin deploying
- **03:27 UTC** — CSI node plugins fail (exit 137) after brief healthy period
- **04:30 UTC** — CSI node job restarted, becomes healthy, prometheus/qdrant start
- **04:33 UTC** — litellm fails: `no space left on device` on octant-01 Podman container storage
- **04:35 UTC** — Podman prune recovers 22.6GB (octant-01), 20.4GB (octant-02), 18.8GB (octant-03)
- **04:38 UTC** — litellm starts but fails: postgres health check critical (connection refused)
- **04:48 UTC** — Docker restart on octant-01 attempted; zombie containers survive
- **05:07 UTC** — CSI mount commands enter D-state; all root-agent containers on octant-01 become unkillable
- **14:15 UTC** — Multiple CSI restart cycles attempted; all fail due to D-state processes
- **15:35 UTC** — `virsh destroy` + `virsh start` on octant-01 clears D-state; clean boot
- **15:37 UTC** — CSI healthy (3/3), postgres/mariadb/prometheus deploy successfully
- **15:43 UTC** — litellm starts successfully

## Root Causes

### 1. CSI RBD volumes not cleanly released before shutdown

The graceful shutdown playbook unmounts CephFS and stops Nomad/Consul, but does not:
- Unpublish CSI volumes (Nomad should do this when jobs stop, but timing matters)
- Unmap RBD kernel devices (`rbd unmap`)

On reboot, stale RBD kernel mappings caused `jbd2` (ext4 journal) threads and `mount` commands to enter uninterruptible sleep (D-state). This made Docker containers using those mounts unkillable.

### 2. Container storage (vdc) full on all three nodes

The 30GB `/var/lib/containers` (Podman rootless) disk was 100% full on octant-01 and 98% on octant-02. Stale images from previous deployments accumulated. The `make deploy-services` flow pulls fresh images, filling the remaining space.

### 3. Service startup ordering

Services deployed simultaneously via Terraform. litellm depends on postgres, but postgres was delayed by CSI volume mount issues. litellm exhausted its restart attempts before postgres became healthy.

### 4. Nomad reschedule exhaustion

When a job exhausts its reschedule attempts, `terraform taint` + `apply` alone doesn't reset the counter — the job appears "changed" but Nomad reuses the failed evaluation. The only reliable fix is `nomad job stop -purge` followed by `terraform apply`.

## Remediation Ideas

### Short-term
- Add `podman system prune -a -f` and `docker system prune -a -f` to the **cluster start playbook** (before services deploy)
- Add a CSI health check gate in the start playbook before declaring the cluster ready
- Document the `nomad job stop -purge` + `terraform apply` pattern for exhausted jobs

### Medium-term
- **Tiered service startup**: Deploy CSI → databases → dependent services (litellm, n8n, etc.) with health gates between tiers
- Consider increasing container storage (vdc) from 30GB to 50GB
- Add Podman/Docker prune as a periodic cleanup job or systemd timer

### Long-term
- Investigate adding CSI volume cleanup (unpublish/unmap) to the graceful shutdown playbook before stopping Nomad
- Consider `restart_policy` tuning: increase `attempts` or use `mode = "delay"` instead of `mode = "fail"` for CSI-dependent services

## Key Learnings

1. **D-state processes survive Docker restart** — only a VM reboot (or `virsh destroy`) clears them
2. **`virsh shutdown` may hang** when D-state processes block the shutdown path — use `virsh destroy` if shutdown doesn't complete within 2 minutes
3. **CSI plugin health counters reset on purge** — `nomad job stop -purge` is the nuclear option that reliably resets all failure state
4. **Container storage needs monitoring** — 30GB fills up quickly across 3 nodes pulling ~20 service images
