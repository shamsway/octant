# Backup Strategy Design

**Date:** 2026-02-26
**Branch:** `feature/app-migration`
**Status:** Approved

## Overview

Self-hosted backup strategy using restic with SFTP to the KVM hypervisor. Designed so switching to S3 (MinIO or Backblaze B2) requires only a config change.

Primary restore scenario: disaster recovery (hypervisor dies, rebuild from scratch on new hardware).

## Architecture

```
  CephFS (/mnt/services/*)
         │
         ├─ pg_dumpall ──► /mnt/services/backups/postgres/    (daily 04:30)
         ├─ mariadb-dump ► /mnt/services/backups/mariadb/     (daily 04:00)
         ├─ consul snap ─► /mnt/services/backups/snapshots/   (daily 02:00)
         ├─ nomad snap ──► /mnt/services/backups/snapshots/   (daily 02:00)
         │
         └─ restic backup (all backup:true volumes) ──────────► SFTP
                                                                  │
                                                     192.168.122.1 (hypervisor)
                                                     /mnt/data/backups/lab/restic-repo
```

DB dumps and state snapshots land on CephFS first. Restic picks them up since `/mnt/services/backups` has `backup: true`. This gives both quick-restore SQL files and deduplicated offsite copies.

## What Gets Backed Up

| Category | What | How | Schedule | Retention |
|----------|------|-----|----------|-----------|
| Service data | `/mnt/services/*` volumes with `backup: true` | Restic SFTP | Daily 02:00 | 180 days |
| Postgres | All databases via `pg_dumpall` | Dump to CephFS | Daily 04:30 | 30 days |
| MariaDB | All databases via `mariadb-dump --all-databases` | Dump to CephFS | Daily 04:00 | 30 days |
| Consul state | `consul snapshot save` | Saved to CephFS, picked up by restic | Daily 02:00 | 180 days |
| Nomad state | `nomad operator snapshot save` | Saved to CephFS, picked up by restic | Daily 02:00 | 180 days |

## Changes Required

### 1. Restic Repository Configuration

Change `restic_repository` in `inventory/group_vars/all.yml`:

```yaml
# Before
restic_repository: "s3:s3.change.me/octant-backup-bucket"

# After
restic_repository: "sftp:admin@192.168.122.1:/mnt/data/backups/lab/restic-repo"
```

SFTP uses SSH key auth. AWS credential variables kept but unused until MinIO/B2 is configured.

### 2. SSH Key Setup for SFTP

The `hashi` user runs Nomad `raw_exec` tasks. Needs SSH access to the hypervisor:

- Generate SSH keypair for `hashi` user on one node
- Distribute public key to all nodes (shared CephFS or Ansible)
- Add public key to hypervisor's `admin` user `authorized_keys`
- Verify: `sudo -u hashi sftp admin@192.168.122.1`

### 3. Backup Script Updates

Port improvements from `octant-private/terraform/restic/backup.sh.tmpl`:

- Add Consul snapshot step: `consul snapshot save /mnt/services/backups/snapshots/consul_TIMESTAMP.snap`
- Add Nomad snapshot step: `nomad operator snapshot save /mnt/services/backups/snapshots/nomad_TIMESTAMP.snap`
- Create snapshot directory before backup
- Keep existing Consul KV result reporting

### 4. MariaDB Backup Job (New)

Create `terraform/mariadb-backup/` mirroring the postgres-backup pattern:

- `main.tf` - Find running mariadb alloc, store in Consul KV, deploy Nomad job
- `variables.tf` - Standard nomad/consul/region/datacenter variables
- `mariadb-backup.nomad.hcl` - Batch job, raw_exec, periodic at `0 4 * * *`
- Uses `nomad alloc exec` to run `mariadb-dump --all-databases` inside the container
- Output: `/mnt/services/backups/mariadb/mariadb_backup_TIMESTAMP.sql.gz`
- Retention: delete dumps older than 30 days
- Credentials: MariaDB root password from Nomad variables (already stored at `nomad/jobs/mariadb`)

### 5. Postgres Backup Fix

The postgres-backup job is not currently deployed:

- Create `/mnt/services/backups/postgres/` directory (via volumes role or manually)
- Run `terraform init && terraform apply` in `terraform/postgres-backup/`
- Verify the Consul KV `service/postgres/alloc` is populated
- Confirm periodic job appears in `nomad job status`

### 6. Backup Directory Structure

Ensure these directories exist on CephFS (add to volumes role if needed):

```
/mnt/services/backups/
├── postgres/       # pg_dumpall output
├── mariadb/        # mariadb-dump output
└── snapshots/      # Consul + Nomad snapshots
```

## Volume Inventory

The inventory has ~44 volumes, ~20 from services not deployed in the VM lab (unifi, homeassistant, 1password, etc.). Restic skips non-existent paths. No cleanup needed.

Currently deployed services with `backup: true` data:

- traefik (data, certs, config)
- postgres (data dir, mode 0700)
- grafana (config)
- nginx (html)
- mariadb (data)
- litellm, n8n (config + data)
- open-webui (config + data)
- phoenix (data)
- searxng (config)
- homepage (config)
- gatus (data)
- uptimekuma (data)
- mosquitto (config)
- backups (the dump directory itself)

## Phase 2: MinIO Migration

When MinIO is deployed:

1. Change `restic_repository` to `s3:http://minio.service.consul:9000/octant-backups`
2. Add MinIO access/secret keys to 1Password and Nomad variables
3. Migrate existing snapshots: `restic copy --from-repo sftp:... --repo s3:...`
4. Keep hypervisor SFTP as secondary/fallback if desired

## Restore Procedures

### Full Cluster Rebuild (DR)

1. Rebuild VMs: `make rebuild-clean`
2. Install restic on one node
3. Mount CephFS
4. `restic restore latest --target /mnt/services/ --repo sftp:admin@192.168.122.1:/mnt/data/backups/lab/restic-repo`
5. Deploy services: `make deploy-services`
6. Restore Consul state: `consul snapshot restore /mnt/services/backups/snapshots/consul_latest.snap`
7. Postgres/MariaDB will auto-recover from restored data dirs

### Single Service Restore

1. Stop the service: `nomad job stop <service>`
2. `restic restore latest --target /tmp/restore --include /mnt/services/<service>/ --repo ...`
3. Copy restored data: `cp -a /tmp/restore/mnt/services/<service>/* /mnt/services/<service>/`
4. Restart: redeploy via terraform

### Database Restore

- Postgres: `gunzip -c /mnt/services/backups/postgres/postgres_backup_LATEST.sql.gz | nomad alloc exec -task postgres <alloc> psql -U postgres`
- MariaDB: `gunzip -c /mnt/services/backups/mariadb/mariadb_backup_LATEST.sql.gz | nomad alloc exec -task mariadb <alloc> mariadb -u root -p$PASS`
