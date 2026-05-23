# Migrating Services from CephFS to CSI RBD

Guide for converting Octant services from CephFS shared-filesystem volumes to dedicated Ceph RBD block devices via the Nomad CSI plugin.

## Why Migrate

CephFS works well for shared config and low-IO workloads, but databases and metrics services benefit from dedicated block devices:

- **I/O isolation** — no contention with other services on the shared filesystem
- **Per-volume sizing** — capacity limits enforced at the Ceph pool level
- **Filesystem choice** — ext4 on RBD vs CephFS (relevant for apps like MongoDB 8 that reject non-standard filesystems)
- **Portability** — CSI volumes can be detached and reattached to different nodes

## Prerequisites

- `ceph-csi` controller and node plugin jobs running (`nomad plugin status ceph-csi` should show all 3 nodes healthy)
- Ceph pool `nomad-csi` exists with the `nomad-csi` user and key
- Service data you're willing to recreate or migrate manually (there is no automatic CephFS-to-RBD data copy)

## Migration Steps

### 1. Create CSI Volume Definition

Create a `<service>-data.hcl` file in `terraform/<service>/`. Use the MongoDB volumes as a template:

```hcl
id        = "<service>-data"
name      = "<service>-data"
type      = "csi"
plugin_id = "ceph-csi"

capacity_min = "5GiB"
capacity_max = "20GiB"    # size appropriately for the service

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  userID  = "nomad-csi"
  userKey = "<ceph-user-key>"    # from: ceph auth get-key client.nomad-csi
}

parameters {
  clusterID     = "<ceph-fsid>"  # from: ceph fsid
  pool          = "nomad-csi"
  imageFeatures = "layering"
  mkfsOptions   = "-t ext4"
}
```

Register the volume:

```bash
nomad volume create terraform/<service>/<service>-data.hcl
```

### 2. Switch Driver from Podman to Docker

CSI volumes require root agents (`meta.rootless = false`). The Docker driver is the standard choice for root-agent tasks.

**Change the constraint:**
```hcl
# Before
constraint {
  attribute = "${meta.rootless}"
  value     = "true"
}

# After
constraint {
  attribute = "${meta.rootless}"
  value     = "false"
}
```

**Change the driver and update syntax:**

| Aspect | Podman | Docker |
|--------|--------|--------|
| `driver` | `"podman"` | `"docker"` |
| `userns` | `userns = "keep-id:uid=70,gid=70"` | Remove (not needed on root agents) |
| `image_pull_timeout` | Supported | Remove (Docker-specific timeout not needed) |
| Logging | `logging = { driver = "journald"; options = [{ "tag" = "name" }] }` | `logging { type = "journald"; config { tag = "name" } }` |

### 3. Replace CephFS Volume Mounts with CSI Volume

**Add a CSI volume block** at the group level:
```hcl
group "<service>" {
  volume "<service>-data" {
    type            = "csi"
    source          = "<service>-data"
    access_mode     = "single-node-writer"
    attachment_mode = "file-system"
  }
  # ...
}
```

**Replace the inline volume mount** in the task config:
```hcl
# Before (Podman inline CephFS mount)
config {
  volumes = [
    "/mnt/services/<service>/data:/var/lib/<service>"
  ]
}

# After (CSI volume_mount block, outside config)
volume_mount {
  volume      = "<service>-data"
  destination = "/var/lib/<service>"
}

config {
  # volumes array removed or only contains non-data mounts (config files, etc.)
}
```

### 4. Pin to a Specific Node (if needed)

Single-instance services should be pinned to a node to ensure the CSI volume is always mounted on the same host:

```hcl
constraint {
  attribute = "${node.unique.name}"
  value     = "octant-01-agent-root"
}
```

For replicated services (like MongoDB's 3-node replica set), use `for_each` in Terraform with a members map — see `terraform/mongodb/` for the pattern.

### 5. Handle Data Migration

CSI RBD volumes start empty. Options for migrating existing data:

**Option A — Fresh start (stateless or easily rebuilt):**
Just deploy. Let the app initialize fresh on the new volume.

**Option B — Copy data before cutover:**
1. Stop the service: `nomad job stop <service>`
2. Create a temporary job that mounts both the CephFS path and the new CSI volume, then copies data between them
3. Or SSH to the node and copy directly: the CSI volume will be mounted under `/opt/nomad/data/` when an allocation claims it

**Option C — Dump and restore (databases):**
1. `pg_dump` / `mysqldump` / `mongodump` while old service is running
2. Stop old service, deploy new service on CSI volume
3. `pg_restore` / `mysql` / `mongorestore` into the new instance

### 6. Apply and Verify

```bash
cd terraform/<service>
terraform plan     # review changes
terraform apply -auto-approve

# If job is dead from previous failures:
nomad job eval <service>

# Verify
nomad job status <service>          # Status = running
nomad alloc logs -job <service>     # No errors
consul catalog services | grep <service>   # Registered
```

## Gotchas

| Issue | Symptom | Fix |
|-------|---------|-----|
| CSI node plugin missing on a node | `nomad volume create` fails or alloc stays pending | `nomad job eval ceph-csi-node` to force placement |
| "bad file" errors | App rejects files on overlay/tmpfs | Write the file to the CSI volume via a prestart init task (see MongoDB keyfile pattern) |
| `nomad job stop` + Terraform | `terraform apply` shows "no changes" after stopping a job via Nomad CLI | Use `terraform taint` to force recreation |
| Wrong node name in constraint | Alloc can't be placed | Root agents are `octant-0N-agent-root`, not `octant-0N` |
| Volume already exists | `nomad volume create` error | Use `nomad volume status <id>` to check; volumes persist across job stops |
| Podman logging syntax with Docker driver | "No argument or block type named 'options'" | Use Docker's `logging { type = "..."; config { ... } }` syntax |
| Init task fails with app image | `unexpected /bin/sh` — app entrypoint intercepts command | Use `busybox:latest` for init tasks that just need `chown`/`chmod` |

## Migration Progress

### Completed

| Service | Date | RBD Size | Data Migration | Notes |
|---------|------|----------|----------------|-------|
| MongoDB (3-node) | 2026-03-08 | 3x 5 GiB | Fresh start | `for_each` pattern, keyfile-init prestart task, Docker driver |
| Prometheus | 2026-03-08 | 10 GiB | Fresh start | busybox volume-init for chown, metrics rebuild from scrape targets |
| MariaDB | 2026-03-09 | 5 GiB | Dump/restore | busybox volume-init for chown (uid 999:999), first dump/restore migration |
| PostgreSQL | 2026-03-09 | 5 GiB | Dump/restore | PGDATA subdirectory needed to avoid ext4 lost+found conflict, 6 dependents stopped/restored |
| Loki | 2026-03-09 | 5 GiB | Fresh start | Logs are ephemeral, busybox volume-init for chown (uid 10001:10001) |
| Neo4j | 2026-03-09 | 5 GiB | Fresh start | uid 7474:7474, community edition needs stop for dump, RBD manual mount for restore |
| Qdrant | 2026-03-09 | 5 GiB | Fresh start | uid 1000:1000 (unprivileged image), busybox volume-init for chown |

### Remaining (Suggested Order)

| Order | Service | Current Size | RBD Size | Data Migration | Backup Job | Notes |
|-------|---------|-------------|----------|----------------|------------|-------|
| 1 | Grafana | 54 MiB | 2-5 GiB | Copy or fresh | Not critical | Low priority — dashboards/config only, minimal I/O benefit |

**Rationale**: Databases with existing backup jobs first (proven dump/restore path), then ephemeral/rebuildable services, then services that need backup jobs created first. Grafana is last because it benefits least from I/O isolation.

## Reference Implementations

### MongoDB (3-node replica set)

See `terraform/mongodb/` for the multi-instance CSI pattern:

- `mongodb.nomad.hcl` — job spec with CSI volume, Docker driver, keyfile-init prestart task
- `mongodb-1-data.hcl` — CSI volume definition
- `main.tf` — `for_each` pattern for multi-instance deployment
- `variables.tf` — members map with node assignments

### Prometheus (single instance)

See `terraform/prometheus/` for the single-instance CSI pattern:

- `prometheus.nomad.hcl` — job spec with CSI volume, Docker driver, busybox volume-init prestart task
- `prometheus-data.hcl` — CSI volume definition
- `main.tf` — `node_name` variable passed to templatefile
- `variables.tf` — `node_name` with default `octant-01-agent-root`
