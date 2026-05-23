# CSI RBD Storage Overview

Reference document covering the Ceph RBD / Nomad CSI setup, capacity planning, and backup implications for migrating services from CephFS to dedicated block devices.

Last updated: 2026-03-08

## Storage Infrastructure

**Ceph Cluster**: 3 OSDs (one per node, 100 GiB each) = 300 GiB raw

| Pool | Replication | Purpose |
|------|-------------|---------|
| `cephfs.octant-services.data` | 2x | Shared filesystem at `/mnt/services/` |
| `cephfs.octant-services.meta` | 2x | CephFS metadata |
| `nomad-csi` | 2x | RBD block devices for CSI volumes |
| `device_health_metrics` | 3x | Ceph internal |

All pools share the same OSDs. With 2x replication, usable capacity is approximately **127 GiB shared** across CephFS and RBD. RBD images are **thin-provisioned** — a 5 GiB volume only consumes space as data is written. The `capacity_max` in volume definitions is a ceiling, not a reservation.

## Current CSI RBD Volumes (as of 2026-03-08)

| Volume | Size | Service | Node |
|--------|------|---------|------|
| `mongodb-1-data` | 5 GiB | mongodb-1 | octant-01-agent-root |
| `mongodb-2-data` | 5 GiB | mongodb-2 | octant-02-agent-root |
| `mongodb-3-data` | 5 GiB | mongodb-3 | octant-03-agent-root |
| `csi-test-vol` | 1 GiB | (test, can delete) | — |

Volume definitions are in `terraform/mongodb/mongodb-N-data.hcl`. Register with `nomad volume create <file>.hcl`.

## Migration Candidates and Sizing

Current CephFS usage and recommended RBD sizes for future migration:

| Service | Current CephFS Size | Suggested RBD Size | Priority | Notes |
|---------|--------------------|--------------------|----------|-------|
| Prometheus | 2.7 GiB | 10–20 GiB | High | Biggest consumer, benefits most from I/O isolation |
| Neo4j | 518 MiB | 5 GiB | Medium | Graph DB, moderate growth |
| MariaDB | 223 MiB | 5 GiB | High | Database, I/O sensitive |
| Qdrant | 220 MiB | 5 GiB | Medium | Vector DB, depends on embedding volume |
| PostgreSQL | 115 MiB | 5 GiB | High | Database, I/O sensitive |
| Loki | 84 MiB | 5–10 GiB | Medium | Log storage, grows with retention |
| Grafana | 54 MiB | 2–5 GiB | Low | Dashboards/config only |

### Capacity Budget

| Category | Allocated |
|----------|-----------|
| MongoDB (existing) | 16 GiB |
| All future migrations (worst-case) | ~60 GiB |
| **Total** | **~76 GiB** |
| **Available** | **~127 GiB** |

No additional Ceph capacity is needed. Headroom allows generous sizing for Prometheus and Loki retention growth.

## Backup Impact

### Database dump jobs — No changes needed

`postgres-backup` and `mariadb-backup` use `nomad alloc exec` to run `pg_dumpall`/`mariadb-dump` inside the running container, piping output to `/mnt/services/backups/`. This approach is **storage-agnostic** — it doesn't matter whether the database files are on CephFS or RBD, because the dump runs inside the container where the volume is already mounted.

### Restic backup — Partial impact

Restic backs up `/mnt/services/` (CephFS). CSI RBD volumes are **not** under `/mnt/services/` — they're mounted directly by the CSI node plugin into the Nomad allocation directory. After migrating a service to RBD:

- Database dump files in `/mnt/services/backups/` are still captured by restic (good)
- Raw data files on the RBD volume are not captured (acceptable — dumps are the restore path)

### Consul/Nomad snapshots — No changes needed

These capture cluster state, not service data.

### Backup job coverage

Every database migrated to RBD must have a corresponding dump job:

| Service | Dump Job | Status |
|---------|----------|--------|
| PostgreSQL | `postgres-backup` (`pg_dumpall`, daily 04:30) | Exists |
| MariaDB | `mariadb-backup` (`mariadb-dump`, daily 04:00) | Exists |
| MongoDB | — | **Needs `mongodb-backup` job using `mongodump`** |
| Prometheus | — | Not needed (metrics are ephemeral/rebuildable) |
| Loki | — | Not needed (logs are ephemeral) |
| Neo4j | — | **Consider `neo4j-admin dump` job** |
| Qdrant | — | **Consider snapshot API job** |

## Prerequisites for Migration

Before migrating any service, verify:

1. `ceph-csi` plugin is healthy: `nomad plugin status ceph-csi` (all 3 nodes healthy)
2. Ceph pool `nomad-csi` exists with the `nomad-csi` user
3. A backup/dump job exists for the service (if it's a database)
4. Downtime window — CSI RBD volumes start empty; data must be dumped and restored

## Related Documents

- [CephFS to CSI RBD Migration Guide](cephfs-to-csi-rbd-migration.md) — step-by-step migration procedure
- [MongoDB Cluster Implementation](../plans/2026-03-07-mongodb-cluster-implementation.md) — first completed migration
- [MongoDB Cluster Design](../plans/2026-03-07-mongodb-cluster-design.md) — architecture decisions
- [Backup Strategy Design](../plans/2026-02-26-backup-strategy-design.md) — overall backup architecture
