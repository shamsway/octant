# BastionClaw Deployment — Progress Summary

**Date:** 2026-02-27
**Branch:** `feature/app-migration`
**Design:** `docs/plans/2026-02-27-bastionclaw-deployment-design.md`
**Implementation Plan:** `docs/plans/2026-02-27-bastionclaw-deployment-implementation.md`

## What Was Completed

All code and configuration tasks (Tasks 1-8) from the implementation plan are done and committed.

### Deliverables

| File | Description | Status |
|---|---|---|
| `inventory/groups.yml` | 4 host volumes (groups, store, data, qmd-models) | Done |
| `terraform/bastionclaw/Dockerfile.orchestrator` | Node.js 22 + podman-docker orchestrator image | Done |
| `terraform/bastionclaw/variables.tf` | 13 Terraform variables with Octant defaults | Done |
| `terraform/bastionclaw/main.tf` | 1Password secrets, Nomad variable, Nomad job | Done |
| `terraform/bastionclaw/bastionclaw.nomad.hcl` | Orchestrator + qmd sidecar Nomad job spec | Done |
| `terraform/bastionclaw/README.md` | Deployment and image build instructions | Done |
| `local/bastionclaw/src/container-runner.ts` | ANTHROPIC_BASE_URL + ANTHROPIC_MODEL in allowedVars, process.env fallback | Done |
| `.gitignore` | Added `local/` exclusion | Done |

### Key Architecture Decisions Made During Implementation

- **Port 13100** (not 3100) — avoids conflict with Loki which uses static port 3100
- **No `connect { native = true }`** — BastionClaw does not participate in Consul service mesh
- **`ANTHROPIC_MODEL=local/glm-5-fp8`** — explicitly routes to the local model via LiteLLM
- **`process.env` fallback in `readSecrets()`** — enables Nomad-injected env vars to reach agent containers (upstream BastionClaw only reads from `.env` files)

### Review Issues Found and Resolved

| Issue | Severity | Resolution |
|---|---|---|
| Port 3100 conflicts with Loki | Critical | Changed to 13100 host / 3100 container |
| Missing ANTHROPIC_MODEL env var | Critical | Added to Nomad env + source allowlist |
| Missing `npm run build:ui` in README | Important | Added to build instructions |
| `connect { native = true }` added then removed | Important | Removed per user feedback |
| Source modification not documented | Suggestion | Added note to README |

## What Remains (Operational Tasks)

These tasks require access to the lab infrastructure and cannot be done from this repo alone.

### Task 9: Pre-seed agent configuration

```bash
# On a Nomad client node as hashi user:
mkdir -p /mnt/services/bastionclaw/groups/main
cat > /mnt/services/bastionclaw/groups/main/CLAUDE.md << 'EOF'
# Agent

You are a general-purpose assistant running on the Octant homelab.
EOF

mkdir -p /mnt/services/bastionclaw/{store,data,qmd-models}
```

Note: Running the Ansible playbook (`ansible-playbook octant.yml`) will create the directories and register Nomad host volumes. The CLAUDE.md must be seeded manually.

### Task 10: Build and push container images

```bash
cd local/bastionclaw

# Build and push agent image
podman build -t registry.service.consul:8082/bastionclaw-agent:latest -f container/Dockerfile container/
podman push registry.service.consul:8082/bastionclaw-agent:latest

# Build and push orchestrator image
npm ci && npm run build && npm run build:ui
podman build -t registry.service.consul:8082/bastionclaw:latest -f ../../terraform/bastionclaw/Dockerfile.orchestrator .
podman push registry.service.consul:8082/bastionclaw:latest
```

### Task 11: Deploy

```bash
cd terraform/bastionclaw
export OP_SERVICE_ACCOUNT_TOKEN="<token>"
terraform apply -auto-approve
```

### Task 12: Validate

```bash
# Nomad job running
nomad job status bastionclaw

# Consul service registered
consul catalog services | grep bastionclaw

# WebUI accessible
curl -sk https://bastionclaw.lab.shamsway.net/ | head

# Agent containers spawn (send a message via WebUI, then check)
podman ps | grep bastionclaw

# LiteLLM receives requests
nomad alloc logs <litellm-alloc-id> | tail
```

## Suggested Next Steps

1. **Run Ansible to provision host volumes** — the volumes added to `inventory/groups.yml` need to be created on the Nomad client nodes and registered as Nomad host volumes
2. **Build container images** — both the orchestrator and agent images need to be built from the modified BastionClaw source and pushed to the internal registry
3. **Deploy and validate** — `terraform apply` + end-to-end testing
4. **Add Telegram/Discord channels** — once WebUI is validated, add messaging channel support by providing bot tokens in 1Password and updating the Nomad env block
5. **Evaluate `connect { native = true }` cleanup** — per user feedback, existing services with this setting should be reviewed and potentially fixed
6. **Consider forking BastionClaw properly** — the source modifications currently live in a git-ignored `local/` clone; a proper fork would make the changes trackable and reproducible
