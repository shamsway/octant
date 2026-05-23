# Session Prompt: Observability & Service Fixes

## Context

Working in `/home/melliott/git/octant/.worktrees/vm-deployment` on branch `feature/app-migration`. This is a VM-based homelab deployment using Ansible roles, Nomad jobs (via Terraform), Consul service discovery, and Traefik reverse proxy. Domain is `lab.shamsway.net`.

Read `docs/plans/2026-02-21-vm-deployment-progress.md` for full project context and `docs/guides/post-deployment-setup.md` for the service reference.

## What's Working

- **Prometheus:** Scraping all targets successfully via Consul SD. The `consul-metrics` catch-all job discovers any service tagged `"metrics"`. 9 exporter targets (3x node-exporter, 3x podman-rootless, 3x podman-rootful) plus traefik-metrics all UP.
- **Grafana:** Datasources provisioned (Prometheus, Loki, Tempo). Node Exporter Full dashboard (1860) imported and working. Accessible at `https://grafana.lab.shamsway.net`.
- **Gatus:** Monitoring 11 endpoints, all configured.
- **Alertmanager:** Running, no notification receivers configured yet (default receiver is empty).
- **Direnv:** `.envrc` exports `TF_VAR_domain`, `TF_VAR_certresolver`, `TF_VAR_nomad`, `TF_VAR_consul` so `terraform apply` in any module dir uses correct values without `-var` flags.

## Tasks (priority order)

### 1. Fix Loki Log Ingestion & Dashboard
Loki is deployed but logs aren't showing up in the Grafana Loki dashboard. The `LokiDown` Prometheus alert was firing. Investigate:
- Is Loki healthy? Check `http://loki.service.consul:3100/ready`
- Is Alloy shipping logs? Alloy runs as a Nomad system job on all nodes, reads `/var/log/journal`, ships to `loki.service.consul:3100/loki/api/v1/push`
- The Nomad journald logging driver may be adding extra newlines to log output - investigate and fix the logging config across Nomad jobs in `terraform/*//*.nomad.hcl`
- Verify the Grafana Loki dashboard (13639) is correctly configured with the Loki datasource

### 2. Fix Homepage "Host validation failed"
The `homepage` service at `https://homepage.lab.shamsway.net` shows "Host validation failed. See logs for more details." Check:
- `terraform/homepage/` for the Nomad job spec and any config
- Homepage uses Consul service discovery tags for widget config - ensure all Nomad jobs have proper homepage tags
- Check homepage container logs via `nomad alloc logs` or Loki

### 3. Uptime Kuma MariaDB Setup
Uptime Kuma is deployed (`https://uptimekuma.lab.shamsway.net`) but needs persistent database storage. Currently using SQLite. To switch to MariaDB:
- Create 1Password secrets for MariaDB user/password for Uptime Kuma (use the existing `seed-onepassword` pattern)
- Create the database and user in the deployed MariaDB instance (`terraform/mariadb/`)
- Update the Uptime Kuma Nomad job to use MariaDB connection string
- Note: Uptime Kuma supports MariaDB, but since our storage is a Ceph cluster, sqlite is not recommended

### 4. Backup Strategy (Design First)
Current state: `roles/restic/` exists for backup. Need to design:
- Option A: Local tarball export - restic backup to local repo, tar it, scp to hypervisor
- Option B: Deploy MinIO as S3-compatible target, configure restic to use it, script offsite transfer
- Consider what data needs backing up: `/mnt/services/*` (all service data), Consul snapshots, Nomad job specs
- This is a design task - use brainstorming skill before implementing

## Architecture Reference

- **Cluster:** 3 VMs (192.168.122.101-103) on KVM hypervisor
- **Services via Terraform:** Each in `terraform/<name>/` with `main.tf`, `variables.tf`, `<name>.nomad.hcl`
- **Ansible roles:** `roles/` directory, playbook is `octant.yml`
- **Deployment:** `make deploy-services` runs all terraform modules via Ansible; `make deploy-role ROLE=<name>` for individual roles
- **Secrets:** 1Password via `OP_SERVICE_ACCOUNT_TOKEN` in `.envrc`, seeded via `make seed-secrets`
- **Sibling repo:** `../octant-private/` has the production bare-metal deployment for reference
