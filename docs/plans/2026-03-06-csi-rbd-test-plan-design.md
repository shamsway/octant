# CSI RBD Test Plan Design — Virtual Cluster

## Purpose

Validate Nomad CSI with Ceph RBD volumes in the virtual cluster before migrating any production workloads. This test plan exercises the full CSI lifecycle (provision, attach, mount, restart, drain, reattach, cleanup) using a SQLite stress-test workload.

This directly supports Phase B (Nomad CSI for RBD) from the [stateful storage migration overview](../../octant-private/docs/plans/2026-03-05-stateful-storage-migration-cephfs-rbd-csi-overview.md) by running the CSI pilot in a safe, isolated environment first.

## Architecture

Four layers, deployed in order:

```
┌─────────────────────────────────────────────────────┐
│  Layer 4: Test Workload (csi-test job)              │
│  - SQLite stress test on CSI volume                 │
│  - Docker driver, root agent                        │
├─────────────────────────────────────────────────────┤
│  Layer 3: CSI Volume (nomad volume create)          │
│  - 1-5 GiB RBD image in nomad-csi pool             │
│  - single-node-writer, ext4                         │
├─────────────────────────────────────────────────────┤
│  Layer 2: CSI Plugin Infrastructure                 │
│  - ceph-csi-controller (service job, Docker)        │
│  - ceph-csi-node (system job, Docker, privileged)   │
│  - Both on root agents (meta.rootless = false)       │
├─────────────────────────────────────────────────────┤
│  Layer 1: Ceph RBD Pool (nomad-csi)                 │
│  - Dedicated pool, size 2 replication               │
│  - Dedicated ceph user (client.nomad-csi)           │
└─────────────────────────────────────────────────────┘
```

## Decision: Docker Driver for CSI Plugins

The CSI node plugin requires `privileged = true` and bidirectional mount propagation (`rshared`). The Podman driver had a known issue with mount propagation (hashicorp/nomad-driver-podman#192). While marked as resolved, nomad-driver-podman 0.6.4 may not fully include the fix.

Decision: Use Docker for CSI plugin jobs. Docker is the battle-tested path documented by both Ceph and HashiCorp. The test workload also uses Docker since rootless support is not needed for CSI validation.

Future work: After Docker-based CSI is proven, attempt a Podman-only deployment to see if 0.6.4 handles the mount propagation correctly.

## File Layout

```
terraform/ceph-csi/                    # CSI plugin infrastructure
  ceph-csi-controller.nomad.hcl        # Controller plugin job spec
  ceph-csi-node.nomad.hcl              # Node plugin job spec (system)
  main.tf                              # Terraform provider + nomad_job resources
  variables.tf                         # ceph_fsid, monitors, csi image tag, etc.

terraform/csi-test/                    # Test workload + volume
  csi-test.nomad.hcl                   # SQLite stress-test job spec
  volume.hcl                           # CSI volume definition for nomad volume create
  main.tf                              # Terraform provider + nomad_job resource
  variables.tf                         # Volume ID, mount path, etc.
```

## Prerequisites

### 1. Ceph RBD Pool

Create a dedicated pool for CSI-provisioned volumes:

```bash
ceph osd pool create nomad-csi 32
ceph osd pool application enable nomad-csi rbd
ceph osd pool set nomad-csi size 2
```

### 2. Dedicated CSI User (Least Privilege)

Scope credentials to the `nomad-csi` pool only:

```bash
ceph auth get-or-create client.nomad-csi \
  mon 'profile rbd' \
  osd 'profile rbd pool=nomad-csi' \
  -o /etc/ceph/ceph.client.nomad-csi.keyring
```

Extract the key for use in volume definitions:

```bash
ceph auth get-key client.nomad-csi
```

### 3. RBD Kernel Module

Verify the `rbd` module is loaded on all nodes:

```bash
ansible servers -i inventory/groups.yml -m shell -a "lsmod | grep rbd"
```

If missing:

```bash
ansible servers -i inventory/groups.yml -m shell -a "sudo modprobe rbd"
```

Persist across reboots:

```bash
ansible servers -i inventory/groups.yml -m shell -a "echo rbd | sudo tee /etc/modules-load.d/rbd.conf"
```

### 4. Docker on Root Agents

Enable Docker alongside Podman on the root agents:

- Set `docker: true` in `inventory/group_vars/all.yml`
- Run the `docker` Ansible role on all nodes
- Restart root Nomad agents to pick up the Docker driver

The root agent template already supports conditional Docker configuration. The Docker plugin config includes `allow_privileged = true` which is required for the CSI node plugin.

### 5. Ceph Cluster FSID and Monitor Addresses

Retrieve for CSI config injection:

```bash
ceph fsid                           # e.g., b9127830-b0cc-4e34-aa47-9d1a2e9949a8
ceph mon dump --format json | jq '.mons[].addr'  # 192.168.122.101-103
```

## CSI Plugin Jobs

### Controller Plugin (`ceph-csi-controller`)

- **Job type:** `service` (single instance)
- **Driver:** `docker`
- **Image:** `quay.io/cephcsi/cephcsi:v3.12.2`
- **Constraint:** `meta.rootless = false` (root agent)
- **Plugin stanza:** `csi_plugin { id = "ceph-csi" type = "controller" mount_dir = "/csi" }`
- **Config injection:** Template block writes ceph-csi config JSON to `local/config.json`, volume-mounted into the container at `/etc/ceph-csi-config/config.json`
- **Args:** `--type=rbd --controllerserver=true --drivername=rbd.csi.ceph.com --endpoint=unix://csi/csi.sock --nodeid=${node.unique.name} --instanceid=${NOMAD_ALLOC_ID} --logtostderr=true --v=5`

### Node Plugin (`ceph-csi-node`)

- **Job type:** `system` (one per eligible node)
- **Driver:** `docker`, `privileged = true`
- **Image:** `quay.io/cephcsi/cephcsi:v3.12.2`
- **Constraint:** `meta.rootless = false` (root agent)
- **Plugin stanza:** `csi_plugin { id = "ceph-csi" type = "node" mount_dir = "/csi" }`
- **Host mounts:**
  - `/sys` -> `/sys` read-write (required — `rbd map` writes to `/sys/bus/rbd/`)
  - `/lib/modules` -> `/lib/modules` read-only (kernel module access)
  - Note: `/dev` is NOT explicitly mounted — Docker `privileged = true` already provides full `/dev` access; an explicit mount causes "Duplicate mount point" errors
- **Config injection:** Same template pattern as controller
- **Args:** `--type=rbd --nodeserver=true --drivername=rbd.csi.ceph.com --endpoint=unix://csi/csi.sock --nodeid=${node.unique.name} --instanceid=${NOMAD_ALLOC_ID} --logtostderr=true --v=5`

### Config JSON Template

Both jobs inject the same config via a Nomad template block:

```json
[{
  "clusterID": "${ceph_fsid}",
  "monitors": [
    "${monitors[0]}",
    "${monitors[1]}",
    "${monitors[2]}"
  ]
}]
```

Where `ceph_fsid` and `monitors` are Terraform variables substituted via `templatefile()`.

## CSI Volume Definition

The volume is created via `nomad volume create volume.hcl`:

```hcl
id        = "csi-test-vol"
name      = "csi-test-vol"
type      = "csi"
plugin_id = "ceph-csi"

capacity_min = "1GiB"
capacity_max = "5GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  userID  = "nomad-csi"
  userKey = "<key from ceph auth get-key client.nomad-csi>"
}

parameters {
  clusterID     = "<ceph fsid>"
  pool          = "nomad-csi"
  imageFeatures = "layering"
  mkfsOptions   = "-t ext4"
}
```

The volume is managed outside Terraform (via `nomad volume create`) because Terraform's `nomad_csi_volume` resource has limitations around CSI volume lifecycle.

## Test Workload

### Container

Alpine + SQLite, running a shell script that:

1. Opens/creates a SQLite database at `/data/test.db`
2. Creates a table (`test_data`) if not exists
3. Counts existing rows (persistence check on restart)
4. Runs continuous write/read/verify cycles:
   - INSERT a row with timestamp + random payload
   - SELECT and verify the row exists
   - Run `PRAGMA integrity_check` periodically
   - Log success count, failure count, and write latency
5. Exposes a simple HTTP health endpoint (via `nc` or a small HTTP server) reporting test status

### Job Spec (`csi-test`)

- **Job type:** `service`
- **Driver:** `docker`
- **Constraint:** `meta.rootless = false`
- **Volume:** CSI volume `csi-test-vol` mounted at `/data`
- **Health check:** HTTP check on the status endpoint
- **Restart policy:** Automatic restarts with delays (validates restart persistence)
- **Reschedule:** Enabled (validates cross-node reattach on drain)

## Validation Scenarios

Run these in order. Each builds on the previous.

### Scenario 1: Plugin Health

After deploying the CSI plugin jobs:

```bash
nomad plugin status ceph-csi
```

**Pass criteria:**
- Controllers Healthy = 1, Controllers Expected = 1
- Nodes Healthy = 3, Nodes Expected = 3
- Provider = `rbd.csi.ceph.com`

### Scenario 2: Volume Creation

```bash
nomad volume create volume.hcl
nomad volume status csi-test-vol
```

**Pass criteria:**
- Volume shows as created with correct capacity
- No errors in controller logs

### Scenario 3: Basic Write/Read

Deploy the test job and wait for it to become healthy.

**Pass criteria:**
- Job status: running, deployment: successful
- SQLite writes/reads succeeding (check logs)
- `PRAGMA integrity_check` passing
- Health check passing in Consul

### Scenario 4: Restart Persistence

Stop and restart the test job:

```bash
nomad job stop csi-test
nomad job run csi-test
```

**Pass criteria:**
- On restart, the test script reports finding existing rows in the database
- No data corruption after restart
- `PRAGMA integrity_check` passes

### Scenario 5: Node Drain and Reattach

Drain the node where the test job is running:

```bash
nomad node drain -enable -yes <node-id>
```

**Pass criteria:**
- Allocation stops cleanly on drained node
- CSI volume detaches from old node (check `nomad volume status`)
- New allocation starts on a different node
- CSI volume attaches to new node
- Test script reports finding existing rows (data survived move)
- No orphaned RBD attachments on old node

After validation:

```bash
nomad node drain -disable <node-id>
```

### Scenario 6: Force-Stop Recovery

Kill the running allocation abruptly:

```bash
nomad alloc stop -f <alloc-id>
```

**Pass criteria:**
- CSI plugin handles cleanup (volume detach)
- Nomad reschedules the allocation
- Volume reattaches on the new allocation
- Data integrity maintained

## Rollback

At any point:

1. Stop the test job: `nomad job stop csi-test`
2. Delete the volume: `nomad volume delete csi-test-vol`
3. Stop CSI plugins: `nomad job stop ceph-csi-controller && nomad job stop ceph-csi-node`
4. Clean up Ceph: `ceph osd pool delete nomad-csi nomad-csi --yes-i-really-mean-it`
5. Revert Docker enablement if desired

No production services are affected. All CSI infrastructure is isolated.

## Success Criteria for Promoting CSI to Production

Before moving any real services to CSI (per the migration overview):

- All six validation scenarios pass
- No orphaned RBD attachments after drain/restart tests
- Attach/detach times are predictable and within tolerance
- Plugin remains healthy across node reboots
- Clear, repeatable recovery steps documented for the top failure modes
- Monitoring coverage: plugin health alerts, volume operation metrics

## Test Results

All validation scenarios passed. CSI RBD is ready for production pilot.

### Scenario Results

| Scenario | Result | Detail |
|----------|--------|--------|
| 1. Basic Write/Read | PASS | 100 writes, 0 failures, `integrity_check = ok` |
| 2. Restart Persistence | PASS | 4,748 rows found at startup after stop/restart |
| 3. Node Drain & Reattach | PASS | 4,873 rows found after drain from octant-02 to octant-01 |
| 4. Force-Stop Recovery | PASS | 4,987 rows found after `nomad alloc stop -f` and reschedule |

### Issues Encountered and Workarounds

**1. Duplicate `/dev` mount (CSI node plugin)**
- **Symptom:** `Duplicate mount point: /dev` error on node plugin start
- **Cause:** Explicit `/dev` bind mount conflicts with Docker `privileged = true`, which already provides full `/dev` access
- **Fix:** Removed the explicit `/dev` bind mount from `ceph-csi-node.nomad.hcl`

**2. Read-only `/sys` blocking RBD map (exit status 30)**
- **Symptom:** `rbd: map failed: (30) Read-only file system` — `rbd map` writes to `/sys/bus/rbd/` to create device mappings
- **Cause:** `/sys` was mounted `readonly = true`
- **Fix:** Changed `/sys` mount to `readonly = false` in `ceph-csi-node.nomad.hcl`

**3. Alpine ash shell incompatibility**
- **Symptom:** `/local/test.sh: line 19: syntax error: unexpected "("`
- **Cause:** BusyBox ash does not support `function_name() { }` syntax
- **Fix:** Rewrote test script using inline loops and a shared `/tmp/status` file for inter-process communication

**4. Stale volume claims after allocation GC**
- **Symptom:** `volume max claims reached` when restarting the test job
- **Cause:** Stopped allocation was GC'd but its CSI claim was not released
- **Fix:** `nomad volume delete -force csi-test-vol` then `nomad volume create volume.hcl` to recreate; `nomad system gc` helps if RBD image is still mapped

### Observed Attach/Detach Behavior

- Volume attach on fresh allocation: near-instant (< 5s)
- Volume detach + reattach during node drain: ~15-30s total (drain → stop → detach → reschedule → attach → start)
- Force-stop recovery: ~30s (Nomad detects failure → reschedule → attach → start)
- No orphaned RBD attachments observed after any scenario

### Production Readiness Verdict

CSI RBD is ready for pilot migration. Recommended next steps:

1. Migrate Prometheus to a CSI volume (low-risk, data is reconstructible from scrape targets)
2. Test Podman driver for CSI plugins (mount propagation in 0.6.4)
3. Once stable, migrate Postgres and other stateful services

Key operational notes for production:
- Always use `nomad system gc` before `nomad volume delete` to clear stale claims
- The `-force` flag on volume delete is required when claims outlive allocations
- CSI node plugin requires `/sys` mounted read-write — this is a hard requirement for `rbd map`
- Docker `privileged = true` already provides `/dev` access; do not add an explicit `/dev` bind mount

## Future Work

- Test Podman driver for CSI plugins (if mount propagation works in 0.6.4)
- Migrate Prometheus to CSI volume (first real service)
- Migrate Postgres to CSI volume (after Prometheus stabilization)
- Add dynamic provisioning (currently using static `nomad volume create`)
