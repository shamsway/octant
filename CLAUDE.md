# Octant Homelab

Infrastructure-as-code for a 3-node homelab running HashiCorp Nomad/Consul with Podman, Ansible, and Terraform.

## Quick Commands

```bash
# Ansible
make deploy                          # Full cluster deployment
make deploy-host HOST=octant-01      # Single host
make deploy-role ROLE=volumes        # Single role, all hosts
make deploy-role-host ROLE=volumes HOST=octant-01

# Terraform (per-service)
cd terraform/<service>
terraform init && terraform plan
terraform apply -auto-approve

# Nomad
nomad job status                     # All jobs
nomad job status <service>           # Specific job
nomad alloc logs -job <service>      # Container logs
nomad alloc logs -job <service> -stderr

# Consul
consul catalog services              # All registered services
consul health state critical         # Failing health checks

# Cluster operations
make start-nomad / make stop-nomad
make start-consul / make stop-consul
make stop-nomad-host HOST=octant-01  # Per-host stop
```

## Architecture

```
Internet → nginx (80/443) → Traefik (Consul catalog) → Nomad services
                                                        ↕
                              Consul DNS (<svc>.service.consul)
                                                        ↕
                              CephFS (/mnt/services/<svc>/)
```

- **3 nodes**: octant-01/02/03 (192.168.122.101-103), each running server + rootless agent + root agent pairs
- **Orchestration**: Nomad with Podman driver
- **Service discovery**: Consul (DNS at `<service>.service.consul`)
- **Ingress**: Traefik with LetsEncrypt via Cloudflare DNS
- **Storage**: CephFS shared filesystem at `/mnt/services/`
- **Secrets**: 1Password + Nomad variables

## Project Structure

```
terraform/<service>/          # Per-service deployment (nomad.hcl + main.tf + variables.tf)
terraform/template/           # Starter template for new services
roles/                        # Ansible roles (consul, nomad, volumes, etc.)
inventory/groups.yml          # Node definitions, volumes, resource allocations
playbooks/                    # Operational playbooks
docs/                         # Infrastructure documentation
local/                        # Local-only projects (gitignored)
```

## Deploying Services

### Plugin System

Octant has a suite of Claude Code plugins installed from the `octant-plugins` marketplace at `~/.claude/plugins/marketplaces/octant-plugins/plugins/`. These plugins contain templates, patterns, and reference documentation for deployments.

**Key plugins:**

| Plugin | Purpose |
|--------|---------|
| `octant` | Architecture overview, skill routing, troubleshooting |
| `octant-autodeploy` | Docker-to-Nomad conversion, deployment workflow, templates |
| `octant-consul-discovery` | Check existing services before deploying |
| `octant-postgres` | Create PostgreSQL databases and users |
| `octant-redis` | Allocate Redis database numbers |
| `octant-volumes` | Create CephFS storage via Ansible |
| `octant-secrets-management` | 1Password secrets + Nomad variables |
| `octant-validation` | Format and validate HCL/Terraform |
| `octant-cloudflare-tunnels` | External access via Cloudflare Zero Trust |

**To use plugins:** Read the SKILL.md from `~/.claude/plugins/marketplaces/octant-plugins/plugins/<plugin-name>/SKILL.md`. The `octant-autodeploy` plugin contains Nomad job templates, Terraform templates, and the full deployment workflow.

### Deployment Pattern

Each service lives in `terraform/<service>/` with three files:

1. **`<service>.nomad.hcl`** — Nomad job spec (HCL templatefile, uses `${var}` for Terraform substitution, `$${var}` for Nomad runtime)
2. **`main.tf`** — Terraform provider + `nomad_job` resource using `templatefile()`
3. **`variables.tf`** — Variable definitions with lab-specific defaults

### Variable Defaults (this lab)

These are the actual defaults used across existing deployments. New services should match:

```hcl
variable "nomad"        { default = "localhost" }
variable "region"       { default = "home" }
variable "datacenter"   { default = "octant" }
variable "domain"       { default = "octant.local" }
variable "certresolver" { default = "" }
variable "dns"          { default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"] }
```

Note: A `.envrc` / tfvars may override `domain` and `certresolver` at runtime for your specific environment.

### Shared Infrastructure

Do not redeploy these — connect to existing instances:
- **PostgreSQL**: `postgres.service.consul:5432`
- **MariaDB**: `mariadb.service.consul:3306`
- **Redis**: `redis.service.consul:6379` (allocate unique DB number 0-15)
- **MinIO**: S3-compatible object storage
- **Local registry**: `192.168.122.1:5000`

## Gotchas

- **Variable escaping in .nomad.hcl**: `${foo}` = Terraform substitutes at plan time. `$${foo}` = Nomad evaluates at runtime. Getting this wrong causes cryptic errors.
- **Rootless vs root**: Most services use `constraint { attribute = "$${meta.rootless}" value = "true" }`. Use `"false"` only for GPU/device access or privileged containers.
- **Health check paths**: IT-Tools, Excalidraw, and other static apps use `/` not `/health`. Check the app's actual health endpoint.
- **Volumes must exist before deploy**: CephFS paths at `/mnt/services/<service>/` must be created via the `octant-volumes` plugin workflow (adds to `inventory/groups.yml`, runs Ansible `volumes` role) before deploying.
- **Template vs templatefile**: Existing services use both `data.template_file` (deprecated) and `templatefile()` (preferred). New services should use `templatefile()`.
- **Traefik tags**: Must include `"traefik.consulcatalog.connect=false"` — without this, Traefik tries to route via Connect sidecar which isn't configured.

## Pre-Commit Hooks

This repo uses [pre-commit](https://pre-commit.com/) hooks for secrets scanning (gitleaks), YAML/Ansible/shell/markdown/Python linting, and basic hygiene (trailing whitespace, large files, private keys). Hooks run automatically on `git commit`.

```bash
# Setup (one-time)
pip install pre-commit && pre-commit install

# Run all hooks locally
pre-commit run --all-files

# Skip all hooks (emergency only)
git commit --no-verify -m "message"

# Skip specific hook(s)
SKIP=gitleaks,ansible-lint git commit -m "message"
```

See [`docs/pre-commit-hooks.md`](docs/pre-commit-hooks.md) for full documentation including inline suppression syntax, troubleshooting, and what is intentionally excluded from linting.

**Note:** Terraform/HCL files are not linted because embedded Nomad `$${var}` syntax breaks standard HCL tools.

## Environment Setup

Copy `envrc.example` to `.envrc` and populate. Key variables:
- `CONSUL_HTTP_ADDR` — Consul API endpoint
- `TAILSCALE_CLOUD_KEY` — Mesh networking
- `CLOUDFLARE_TOKEN` — DNS/TLS certificates
- `OP_SERVICE_ACCOUNT_TOKEN` — 1Password integration (implicit)
