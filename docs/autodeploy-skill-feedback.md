# Autodeploy Skill Feedback

**Date**: 2026-02-28
**Deployments tested**: Gitea (Easy/M3), Linkwarden (Medium/M4 — first Postgres test)

---

## Issues Found

### 1. 1Password Vault Name — All Skills

**Affected skills**: `octant-postgres`, `octant-secrets-management`

The skills reference vault `Dev` throughout, but the actual vault name is `Octant`. Every `--vault Dev` and `op://Dev/` reference needs updating to `--vault Octant` and `op://Octant/`.

**Examples to fix in `octant-postgres`:**
```bash
# Current (broken)
op read "op://Dev/service_postgres/password"
op item create --vault Dev ...

# Correct
op read "op://Octant/service_postgres/password"
op item create --vault Octant ...
```

**Examples to fix in `octant-secrets-management`:**
```bash
# Current (broken)
op item list --vault Dev
op item get api_anthropic_key --vault Dev

# Correct
op item list --vault Octant
op item get api_anthropic_key --vault Octant
```

---

### 2. Consul DNS Not Resolvable from Dev Machine — `octant-postgres`

The `octant-postgres` skill uses `postgres.service.consul` for all `psql` commands, but Consul DNS doesn't resolve from the dev workstation. Commands fail with `could not translate host name`.

**Recommendation**: Add a note or fallback in the skill:
```bash
# If Consul DNS doesn't resolve from your machine, use a node IP directly:
POSTGRES_HOST="192.168.122.101"  # Fallback when postgres.service.consul doesn't resolve
```

The Nomad job templates should still use `postgres.service.consul` (it resolves inside the cluster), but the setup scripts run from the dev machine need the IP fallback.

---

### 3. Health Check Path Guidance — `octant-autodeploy`

The template defaults to `/health`, but many apps don't have a dedicated health endpoint. The skill should provide guidance on discovering the correct path.

**Apps tested and their actual health endpoints:**
| App | Health Path | Notes |
|-----|------------|-------|
| IT-Tools | `/` | Static web app |
| Fusion | `/` | Go app, no /health |
| Linkding | `/health` | Actually has one |
| Gitea | `/api/healthz` | Documented API endpoint |
| Linkwarden | `/` | Next.js app, no health endpoint |

**Recommendation**: Add to the template/checklist:
- Check the app's documentation for a health endpoint
- Try `/health`, `/healthz`, `/api/health`, `/api/healthz` in order
- Fall back to `/` if none exists (returns 200 for most web apps)
- Next.js apps typically don't have health endpoints — use `/`

---

### 4. Memory Sizing Guidance — `octant-autodeploy`

The template uses placeholder `<MEMORY_MB>` but doesn't provide guidance on sizing. During testing:

| App Type | Minimum Memory | Notes |
|----------|---------------|-------|
| Static/Go (IT-Tools, Fusion) | 256 MB | Lightweight |
| Python/Ruby | 256-512 MB | Depends on framework |
| Java/JVM | 512-1024 MB | JVM overhead |
| Next.js/Node.js (Linkwarden) | 1024 MB | Worker process OOM-killed at 512 MB |
| Git forge (Gitea) | 512 MB | Stable at 512 |

**Recommendation**: Add a sizing guide to the Docker Compose Mapping section:
```
deploy.resources.limits.memory: 512m → resources { memory = 512 }

If no memory limit in compose file, use these defaults:
- Static/Go apps: 256 MB
- Node.js/Next.js apps: 1024 MB
- Java apps: 1024 MB
- Everything else: 512 MB
```

---

### 5. `nomad alloc logs` stderr flag — `octant-autodeploy`

The troubleshooting section shows:
```bash
nomad alloc logs -job <jobname> -stderr
```

This doesn't work — `-stderr` gets parsed as a task name, returning `unknown task name "-stderr"`. The correct usage requires the alloc ID:

```bash
# Get the alloc ID first
ALLOC_ID=$(nomad job allocs -job <jobname> -json | jq -r '.[0].ID')
nomad alloc logs ${ALLOC_ID} -stderr
```

Or use the two-step approach:
```bash
nomad alloc logs -job <jobname>          # stdout works with -job
nomad alloc logs <alloc-id> -stderr      # stderr requires alloc ID
```

---

### 6. Nomad Variable Template Pattern — `octant-postgres`

The integration example in `octant-postgres` shows:
```hcl
template {
  destination = "${NOMAD_SECRETS_DIR}/env.txt"
```

This is missing the `$$` escape. Should be:
```hcl
template {
  destination = "$${NOMAD_SECRETS_DIR}/env.txt"
```

Without the escape, Terraform tries to substitute `NOMAD_SECRETS_DIR` at plan time (and it doesn't exist as a Terraform variable).

---

### 7. Postgres Setup Script Uses Pipe Operator — `octant-postgres`

The "Complete Service Setup Script" pipes SQL through heredoc to `psql`, but `CREATE DATABASE` and `\c` in the same session can be fragile. The script also doesn't handle the case where the database or user already exists (no `IF NOT EXISTS`).

**Recommendation**: Add `IF NOT EXISTS` guards:
```sql
SELECT 'CREATE DATABASE linkwarden' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'linkwarden')\gexec
CREATE USER IF NOT EXISTS ...
```

Or at minimum, note that errors from "already exists" are safe to ignore.

---

## What Worked Well

- The Fusion deployment pattern was an excellent reference — clean, minimal, easy to adapt
- The `templatefile()` approach with `jsonencode(var.dns)` works reliably
- The Nomad variable + template pattern for secrets injection is clean and avoids putting secrets in HCL files
- The volumes workflow (inventory → Ansible playbook) is solid and idempotent
- Traefik tag pattern with `consulcatalog.connect=false` is consistent and works every time

---

## Suggested Skill Improvements Summary

| Priority | Skill | Change |
|----------|-------|--------|
| **Critical** | `octant-postgres`, `octant-secrets-management` | Change vault `Dev` → `Octant` |
| **High** | `octant-postgres` | Add node IP fallback for psql from dev machine |
| **High** | `octant-postgres` | Fix `${NOMAD_SECRETS_DIR}` → `$${NOMAD_SECRETS_DIR}` in template example |
| **High** | `octant-autodeploy` | Fix `nomad alloc logs -job <name> -stderr` syntax |
| **Medium** | `octant-autodeploy` | Add health check discovery guidance |
| **Medium** | `octant-autodeploy` | Add memory sizing guide by app type |
| **Low** | `octant-postgres` | Add `IF NOT EXISTS` guards to setup script |
