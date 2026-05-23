# App Migration & Rebrand Design

**Date:** 2026-02-24
**Branch:** `feature/app-migration` (based on `feature/vm-deployment`)
**Goal:** Migrate 25 application deployment configs from octant-private, rebrand homelab -> octant, add DNS tier support, and validate with full rebuild

## Context

The VM deployment (feature/vm-deployment) has a working 3-node cluster with Consul, Nomad, Ceph, and 4 deployed services (Traefik, Postgres, LiteLLM, Registry). This design covers migrating additional apps from the production repo (octant-private), rebranding all "homelab" references to "octant", and adding configurable DNS/TLS support.

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Incomplete modules (nomad-only) | Create full Terraform modules | Uniform deployment via terraform_execution_order |
| Cloudflare tunnels | Strip, Traefik-only routing | VM environment is local network; Cloudflare added later if needed |
| Rebrand scope | Full rebrand including /opt/homelab/ paths | Clean break, no legacy naming |
| DNS strategy | Two tiers: sslip.io default + Cloudflare opt-in | Zero-config for new users, real HTTPS for production use |
| 1Password seeding | Ansible role (seed-onepassword) | Integrated into deploy pipeline, idempotent |
| External API key deps | Two-tier apps: core (no ext deps) + optional | Optional apps fail gracefully when secrets missing |
| Migration approach | Batch migration in phased order | Common patterns make per-app work mechanical |
| Subdomain support | Fully supported (e.g. lab.octant.net) | Domain variable propagates to all modules |

## Phase 1: Foundation & Rebrand

### Full Rebrand (homelab -> octant)

73 occurrences across the codebase in 4 categories:

**File rename:**
- `homelab.yml` -> `octant.yml`

**Path references (24 occurrences in group_vars/all.yml):**
- `configdir: /opt/homelab/config` -> `configdir: /opt/octant/config`
- `datadir: /opt/homelab/data` -> `datadir: /opt/octant/data`
- All sub-paths (`consul-server.d`, `nomad-server.d`, etc.) inherit from these base variables

**Playbook imports & Makefile (13 occurrences):**
- `playbooks/site.yml`: update import path
- `Makefile`: update all targets referencing `homelab.yml`
- `playbooks/01-provision-vms.yml`, `02-deploy-ceph.yml`, `03-deploy-services.yml`: update comments

**Documentation (~35 occurrences):**
- README.md, docs/, plans/: update references
- "homelab framework" -> "Octant framework"
- Generic "homelab" category references -> "lab" or "environment"

### DNS Tier Support

**Tier 1 - sslip.io (zero-config default):**
- Default `domain` set to sslip.io-based value derived from Traefik node IP
- HTTP only, no certresolver configured
- Works on locked-down clients without DNS resolver changes

**Tier 2 - Cloudflare + real domain (documented opt-in):**
- User sets `domain` variable (e.g., `lab.octant.net`)
- User sets `certresolver` to `cloudflare`
- Cloudflare API token stored in 1Password
- Traefik uses DNS-01 ACME challenge for wildcard cert (`*.lab.octant.net`)
- Wildcard A record (DNS-only/grey cloud) in Cloudflare pointing to Traefik node IP
- Free tier supports DNS-only deeper-level wildcards and DNS-01 challenges

**Subdomain support:**
- `*.lab.octant.net` works on Cloudflare free tier as DNS-only record
- Let's Encrypt DNS-01 places TXT at `_acme-challenge.lab.octant.net` - works fine
- Consul service discovery (`grafana.service.consul`) is independent of external domain
- All modules use `${domain}` variable - no per-module changes needed

**Implementation:**
- `domain` and `certresolver` defaults in `group_vars/all.yml`
- Traefik nomad job conditionally includes TLS config based on certresolver
- Documentation in `docs/dns-setup.md`

## Phase 2: Core App Migration

### Module Adaptation Pattern

Applied to every migrated module:

1. 1Password provider: empty block (SaaS auth via `OP_SERVICE_ACCOUNT_TOKEN` env var)
2. Vault reference: `var.op_vault_name` defaulting to `"Octant"`
3. Nomad address: `var.nomad` defaulting to `"localhost"`
4. Consul address: `var.consul` defaulting to `"localhost"`
5. Datacenter: `var.datacenter` defaulting to `"octant"`
6. Domain: `var.domain` using configured default
7. DNS: `var.dns` defaulting to `["192.168.122.1"]` (libvirt gateway)
8. Strip all Cloudflare tunnel/DNS resources
9. Replace deprecated `data "template_file"` with `templatefile()` function
10. Normalize `shared_dir` from `/opt/storage/` to `/mnt/services/` (CephFS mount)
11. Normalize all hardcoded domain references to use `var.domain`

### Core Apps (deploy by default, no external API keys)

| App | Source State | Notes |
|-----|-------------|-------|
| traefik | Exists | Add DNS-01 certresolver, update defaults |
| postgres | Exists | Check for improvements from private |
| litellm | Exists | Check improvements; starts without API keys |
| registry | Exists (commented) | Uncomment, verify |
| mariadb | TF in private | 1Password for root password |
| nginx | Nomad-only | Create full TF module |
| excalidraw | Nomad-only | Create full TF module, no secrets |
| mqtt | Nomad-only | Create full TF module, no secrets |
| pgadmin | TF in private | Normalize 1Password provider |
| qdrant | TF in private | Consul integration |
| searxng | TF in private | Includes redis sidecar |
| uptimekuma | TF in private | Simple, no secrets |
| homepage | TF in private | Config generation |

## Phase 3: Observability Stack

Deployed as a unit (Grafana needs the others as datasources):

| App | Notes |
|-----|-------|
| prometheus | Metrics collection, no secrets |
| loki | Log aggregation, no secrets |
| tempo | Distributed tracing, no secrets |
| alertmanager | Alert routing, YAML config |
| alloy | Telemetry collector, config file |
| grafana | Visualization, datasources config for loki/prometheus/tempo |
| gatus | Endpoint health, YAML config |

## Phase 4: Optional Apps

Require manual 1Password items with external API keys. Fail gracefully when secrets are missing - Terraform errors on the specific module but other modules continue.

| App | External Dependencies |
|-----|-----------------------|
| n8n | Postgres creds (auto-seeded), Cloudflare stripped |
| open-webui | LiteLLM API key |
| phoenix | Postgres creds (auto-seeded) |
| openclaw-gateway | Discord, Slack, Anthropic, Moonshot, ZAI API keys |
| ntfy | SMTP/SendGrid creds, Cloudflare stripped |

## Terraform Execution Order

```yaml
terraform_execution_order:
  # Core infrastructure
  - traefik
  - postgres
  - registry
  - mariadb
  - nginx
  - mqtt
  - excalidraw
  - qdrant
  - searxng
  - uptimekuma
  - pgadmin
  - homepage
  # Observability stack
  - prometheus
  - loki
  - tempo
  - alertmanager
  - alloy
  - grafana
  - gatus
  # LLM stack
  - litellm
  # Optional (require external config)
  - n8n
  - open-webui
  - phoenix
  - openclaw-gateway
  - ntfy
```

## 1Password Seeding

### New Role: seed-onepassword

Runs before Terraform in `03-deploy-services.yml`, or standalone via `make seed-secrets`.

**Behavior:**
- Uses `op` CLI via `OP_SERVICE_ACCOUNT_TOKEN`
- Checks if each required item exists in configured vault
- Creates missing items with generated passwords (32-char, no symbols)
- Skips existing items (idempotent)
- Logs clear messages for optional apps with missing external credentials

**Auto-seeded items (core apps):**

| 1Password Item | Used By | Fields |
|----------------|---------|--------|
| Postgres | postgres, pgadmin | username, password |
| postgres_litellm | litellm | username, password |
| postgres_n8n | n8n | username, password |
| postgres_phoenix | phoenix | username, password |
| service_mariadb | mariadb | password |

**Not auto-seeded (user-provided):**

| Item | Reason |
|------|--------|
| OpenAI/Anthropic/etc. API keys | External service credentials |
| Discord/Slack tokens | External service credentials |
| SendGrid credentials | External service credentials |
| Cloudflare API token | Tier 2 DNS only |

## Decommission Nautobot

- Exclude from migration (do not copy from octant-private)
- Do not add to terraform_execution_order

## Phase 5: Validation & Cleanup

**Full `make rebuild` test:**
- Teardown existing cluster
- Full deploy from scratch
- Verify all core apps deploy
- Verify optional apps fail gracefully when secrets missing
- Health check passes

**Cleanup:**
- Remove stale commented-out code
- Update progress tracker
- Update design doc with final state
- Clean commit history before merge
