# Graceful Cluster Shutdown & Snapshot Design

**Date:** 2026-03-10
**Branch:** feature/app-migration

## Purpose

General-purpose playbooks for gracefully shutting down the Octant cluster and creating OS-level VM disk snapshots. Covers maintenance windows, extended downtime, and pre-upgrade safety nets.

## Architecture

Two playbooks in sequence:

1. `playbooks/08-graceful-shutdown.yml` — stops all services and daemons in dependency order
2. `playbooks/09-snapshot-cluster.yml` — creates qcow2 external snapshots of stopped VM OS disks

Startup is handled by systemd (auto-starts Ceph, Consul, Nomad on boot) and Nomad (restarts jobs). No dedicated startup playbook needed.

## Graceful Shutdown Playbook

**File:** `playbooks/08-graceful-shutdown.yml`

**Usage:**
```bash
make shutdown                                    # Interactive (confirmation prompt)
make shutdown ARGS="-e confirm_shutdown=yes"      # Skip prompt
```

### Phase Sequence

**Play 1 — localhost (terraform destroy):**

| Phase | Actions |
|-------|---------|
| Pre-flight | Verify Consul API (port 8500) and Nomad API (port 4646) are reachable |
| Confirmation | Display service inventory, prompt for confirmation (skippable via `-e confirm_shutdown=yes`) |
| Save state | Record running Nomad jobs and Consul service catalog to `playbooks/.shutdown-state/shutdown-state.yml` |
| Terraform destroy | Use `apply-terraform` role with `terraform_action: destroy`, `modules: terraform_execution_order \| reverse` |

**Play 2 — servers (Ceph, Nomad, Consul):**

| Phase | Actions |
|-------|---------|
| Ceph maintenance | Set OSD flags: `noout`, `nobackfill`, `norecover`. Verify flags are set. |
| CephFS unmount | Unmount `/mnt/services` on all 3 nodes (`state: unmounted`, preserves fstab entry for auto-remount on boot) |
| Stop Nomad | Stop `nomad-agent`, `nomad-agent-root`, `nomad-server` on all nodes (serial: 1) |
| Stop Consul | Stop `consul-agent`, `consul-agent-root`, `consul-server` on all nodes (serial: 1) |
| Summary | Display final service states, Ceph flag status, and post-restart instructions |

### Ceph Handling

**Why `noout` is critical:** Without it, Ceph marks OSDs as "out" after 10 minutes (`mon_osd_down_out_interval`) and triggers data rebalancing. With a 3-node cluster, this can be especially disruptive since rebalancing targets nodes that are also about to go down.

**Why flags stay set through restart:** On boot, OSDs start staggered across nodes. The flags prevent Ceph from rebalancing during this window. After all OSDs are up and `ceph health` shows healthy (or only flag warnings), the operator runs:
```bash
ceph osd unset noout && ceph osd unset nobackfill && ceph osd unset norecover
```

**CephFS unmount:** Uses `ansible.posix.mount` with `state: unmounted` — removes the active mount but leaves the fstab entry intact. On next boot, systemd re-mounts via fstab (`_netdev` option ensures it waits for network).

### Design Decisions

- **Single orchestration playbook** over composable scripts: gives confirmation prompts, phase-by-phase visibility, and proper error handling between phases.
- **Two plays in one playbook:** Play 1 runs on localhost for terraform operations. Play 2 runs on servers for system-level operations. This matches existing patterns (`06-destroy-services.yml` runs on localhost, `stop-nomad.yml` runs on servers).
- **Reuses `apply-terraform` role:** Same logic as `06-destroy-services.yml`, no duplication.
- **Execution order services only:** Manually-deployed services (mongodb, ceph-csi, openclaw-gateway, etc.) are the operator's responsibility to stop beforehand.
- **Ceph commands delegated to first server:** `ceph osd set` commands run via SSH on the first node in the servers group, since cephadm CLI is on the VMs.

## Snapshot Playbook

**File:** `playbooks/09-snapshot-cluster.yml`

**Usage:**
```bash
make snapshot                                      # Auto-named: snapshot-YYYYMMDDTHHMMSS
make snapshot ARGS="-e snapshot_name=pre-upgrade"   # Custom name
make snapshot ARGS="-e list_snapshots=true"         # List existing snapshots
```

**Prerequisites:** All cluster VMs must be shut off (`make shutdown` first, then shut down VMs).

### What Gets Snapshotted

**OS disk only (vda, qcow2, 60G per VM).** Data disk (vdb, Ceph OSD) and container disk (vdc, Podman storage) are explicitly excluded.

Rationale: Application data lives on Ceph (CephFS + CSI RBD) and is backed up via Restic and database dump jobs. The OS snapshot captures Nomad/Consul data directories (`/opt/octant/data/`), systemd configs, Ceph client config (`/etc/ceph/`), SSH keys, and all other OS-level state.

### Phase Sequence

| Phase | Actions |
|-------|---------|
| Verify VMs stopped | `virsh domstate` for each VM in `groups['servers']`. Fail if any are running. |
| Check name collision | Fail if `playbooks/.snapshots/<name>/` already exists |
| Save pre-snapshot state | Export `virsh dumpxml` for each VM. Discover disk paths via `virsh domblklist`. Save `snapshot-metadata.yml`. |
| Create snapshots | `virsh snapshot-create-as` with `--disk-only --atomic --no-metadata`. Only vda gets `snapshot=external`; vdb and vdc get `snapshot=no`. |
| Verify | Confirm overlay files exist. Confirm VM definitions now point to overlays. Display summary with next steps. |

### Snapshot Mechanism

Uses KVM external snapshots. The current OS disk becomes a read-only snapshot point. A new qcow2 overlay file is created for future writes. Restoring means reverting to the original disk.

Overlay files are created alongside the original disk:
```
/var/lib/libvirt/images/octant-01.qcow2                        # Original (read-only after snapshot)
/var/lib/libvirt/images/octant-01.<snapshot-name>.qcow2         # Overlay (new writes go here)
```

## File Layout

### New Files

| File | Purpose |
|------|---------|
| `playbooks/08-graceful-shutdown.yml` | Orchestrates full shutdown sequence |
| `playbooks/09-snapshot-cluster.yml` | Creates OS disk snapshots of stopped VMs |

### Makefile Targets

```makefile
shutdown:
	ansible-playbook playbooks/08-graceful-shutdown.yml $(VM_CLUSTER_INVENTORY) $(ARGS)

snapshot:
	ansible-playbook playbooks/09-snapshot-cluster.yml -i inventory/hypervisors.yml -i inventory/groups.yml $(ARGS)
```

`shutdown` uses `VM_CLUSTER_INVENTORY` (needs provisioned_vms.yml + groups.yml for terraform destroy and SSH to nodes). `snapshot` needs both `hypervisors.yml` (virsh runs on hypervisor) and `groups.yml` (playbook references `groups['servers']` for the VM list).

### Runtime Artifacts (gitignored)

```
playbooks/.shutdown-state/
  └── shutdown-state.yml          # Last shutdown metadata

playbooks/.snapshots/
  └── <snapshot-name>/
      ├── snapshot-metadata.yml   # Disk paths, overlay paths, timestamp
      ├── octant-01-domain.xml
      ├── octant-02-domain.xml
      └── octant-03-domain.xml
```

## Post-Restart Checklist

After VMs boot and services auto-start:

1. Verify Ceph health: `ssh octant-01 'sudo ceph health'`
2. Unset OSD flags: `ssh octant-01 'sudo ceph osd unset noout && sudo ceph osd unset nobackfill && sudo ceph osd unset norecover'`
3. Verify CephFS is mounted: `ssh octant-01 'df -h /mnt/services'`
4. Verify Nomad jobs: `nomad job status`
5. If jobs didn't restart: `make deploy-services` or `cd terraform/<service> && terraform apply`
