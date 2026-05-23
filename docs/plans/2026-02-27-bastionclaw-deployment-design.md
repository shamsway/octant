# BastionClaw Deployment - Design

**Date:** 2026-02-27
**Branch:** `feature/app-migration`
**Status:** Approved

## Goal

Deploy BastionClaw as a containerized personal AI assistant on Octant, using Podman-out-of-Podman via socket mount, with a single agent backed by the local glm-5-fp8 model through LiteLLM.

## Context

Octant currently runs OpenClaw Gateway for AI assistant capabilities. BastionClaw (a fork of NanoClaw) offers a lighter-weight alternative with OS-level container isolation for agent execution. BastionClaw is architecturally a container orchestrator itself — it spawns ephemeral Podman containers for each agent session, providing sandboxed code execution, web browsing, and file access.

The reference repo is cloned at `local/bastionclaw/` (git-ignored). The existing `terraform/openclaw-gateway/` provides the deployment pattern to follow.

Key challenge: BastionClaw expects to run as a host process and spawn containers directly. Running it inside a Nomad-managed Podman container requires the "Podman-out-of-Podman" pattern — mounting the host's rootless Podman socket into the orchestrator container so it can spawn sibling agent containers.

## Architecture

```
Internet / LAN
  │
  ▼
Traefik (bastionclaw.lab.shamsway.net)
  │
  ▼ Consul service discovery
  │
Nomad job: bastionclaw (constraint: meta.rootless=true)
  │
  └── Group: bastionclaw
       │
       ├── Task: orchestrator (podman driver)
       │   ├── Image: registry.service.consul:8082/bastionclaw:latest
       │   ├── Port: 3100 (WebUI)
       │   ├── Mounts:
       │   │   ├── /run/user/2000/podman/podman.sock → /run/podman/podman.sock
       │   │   ├── /mnt/services/bastionclaw/groups   → /app/groups
       │   │   ├── /mnt/services/bastionclaw/store    → /app/store
       │   │   └── /mnt/services/bastionclaw/data     → /app/data
       │   ├── Env:
       │   │   ├── DOCKER_HOST=unix:///run/podman/podman.sock
       │   │   ├── ANTHROPIC_BASE_URL=http://litellm.service.consul:4000
       │   │   ├── CONTAINER_IMAGE=registry.service.consul:8082/bastionclaw-agent:latest
       │   │   └── WEBUI_HOST=0.0.0.0
       │   └── Secrets (Nomad vars): ANTHROPIC_API_KEY, LITELLM_API_KEY
       │
       ├── Task: qmd (podman driver, sidecar)
       │   ├── Image: registry.service.consul:8082/bastionclaw:latest
       │   ├── Entrypoint: qmd serve
       │   ├── Mounts: shared groups/, data/, qmd-models/
       │   └── Port: 8181 (localhost only, within group network)
       │
       └── spawns via socket ──► Sibling agent containers (rootless Podman)
                                  ├── bastionclaw-agent:latest
                                  ├── Claude Agent SDK + Chromium
                                  ├── ANTHROPIC_BASE_URL → LiteLLM
                                  └── Queries local/glm-5-fp8 model
                                       │
                                       ▼
                                  LiteLLM (litellm.service.consul:4000)
                                       │
                                       ▼
                                  vLLM on hypervisor (192.168.122.1:8000)
                                       │
                                       ▼
                                  glm-5-fp8 (local GPU)
```

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Nomad driver | Podman with socket mount | Aligns with rootless Podman pattern; raw_exec requires root-level Nomad client |
| Socket mount pattern | Mount hashi user's rootless socket (`/run/user/2000/podman/podman.sock`) | Proven pattern — podman-exporter already does this in Octant |
| Agent containers | Sibling containers via socket (Podman-out-of-Podman) | Preserves BastionClaw's security model; no nesting complexity |
| LLM backend | LiteLLM proxy → local glm-5-fp8 | Reuses existing LiteLLM infrastructure; no direct API calls needed |
| Channels | WebUI only (port 3100) | Simplest initial deployment; Telegram/Discord can be added later |
| Memory system | Include qmd | Enables semantic memory from day one; worth the complexity |
| Container image CLI | `podman-docker` package in orchestrator image | Provides `docker` command wrapper so BastionClaw's runtime detection works |
| Hostname | `bastionclaw.lab.shamsway.net` | Matches existing deployed services |
| Storage | `/mnt/services/bastionclaw/` | Follows Octant volume conventions |

## What Gets Changed

| Component | Current State | Target State | Notes |
|-----------|--------------|--------------|-------|
| `terraform/bastionclaw/` | Does not exist | New Terraform module | main.tf, variables.tf, bastionclaw.nomad.hcl, Dockerfile.orchestrator, README.md |
| `inventory/groups.yml` | No bastionclaw volumes | Add 4 host volumes | groups, store, data, qmd-models |
| BastionClaw `src/container-runner.ts` | `ANTHROPIC_BASE_URL` not in allowedVars | Added to allowlist | Enables LiteLLM passthrough to agent containers |
| `/mnt/services/bastionclaw/` | Does not exist | Created with subdirs | groups/, store/, data/, qmd-models/ |

## Implementation Sections

### Section 1: Host Volume Preparation

Add volumes to `inventory/groups.yml` under the servers group:

```yaml
- name: bastionclaw-groups
  path: /mnt/services/bastionclaw/groups
  backup: true
- name: bastionclaw-store
  path: /mnt/services/bastionclaw/store
  backup: true
- name: bastionclaw-data
  path: /mnt/services/bastionclaw/data
  backup: true
- name: bastionclaw-qmd-models
  path: /mnt/services/bastionclaw/qmd-models
  backup: false
```

Run the Ansible playbook to create directories and register Nomad host volumes.

### Section 2: BastionClaw Source Modification

Fork BastionClaw source with a single change to `src/container-runner.ts`:

```typescript
// Before
const allowedVars = ['CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_API_KEY',
                     'TRANSCRIPT_API_KEY', 'GEMINI_API_KEY'];

// After
const allowedVars = ['CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_API_KEY',
                     'TRANSCRIPT_API_KEY', 'GEMINI_API_KEY',
                     'ANTHROPIC_BASE_URL'];
```

### Section 3: Container Images

**Orchestrator image** (`terraform/bastionclaw/Dockerfile.orchestrator`):

```dockerfile
FROM node:22-slim
RUN apt-get update && apt-get install -y podman-docker && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY dist/ ./dist/
COPY container/ ./container/
EXPOSE 3100
CMD ["node", "dist/index.js"]
```

**Agent image** — use BastionClaw's existing `container/Dockerfile` as-is. Build and push to internal registry:

```bash
# From bastionclaw source directory
podman build -t registry.service.consul:8082/bastionclaw-agent:latest -f container/Dockerfile .
podman push registry.service.consul:8082/bastionclaw-agent:latest

# Orchestrator
npm run build  # compile TypeScript
podman build -t registry.service.consul:8082/bastionclaw:latest -f Dockerfile.orchestrator .
podman push registry.service.consul:8082/bastionclaw:latest
```

### Section 4: Terraform Module

**`terraform/bastionclaw/variables.tf`** — standard Octant variables plus:

| Variable | Default | Purpose |
|----------|---------|---------|
| `image` | `registry.service.consul:8082/bastionclaw:latest` | Orchestrator image |
| `agent_image` | `registry.service.consul:8082/bastionclaw-agent:latest` | Agent container image |
| `domain` | `lab.shamsway.net` | Traefik routing domain |
| `certresolver` | `""` | TLS cert resolver |
| `servicename` | `bastionclaw` | Consul service name |
| `litellm_base_url` | `http://litellm.service.consul:4000` | LiteLLM proxy URL |
| `podman_socket_path` | `/run/user/2000/podman/podman.sock` | Host Podman socket |

**`terraform/bastionclaw/main.tf`** — 1Password secrets:
- Reuses existing `api_anthropic_key` and `service_litellm` items
- Stores in Nomad variable at `nomad/jobs/bastionclaw`

**`terraform/bastionclaw/bastionclaw.nomad.hcl`** — two tasks in one group:
- `orchestrator`: Podman driver, port 3100, socket mount, persistent volumes
- `qmd`: Podman driver, same image with qmd entrypoint, shared volumes

### Section 5: Agent Configuration

Pre-seed the main agent's CLAUDE.md at `/mnt/services/bastionclaw/groups/main/CLAUDE.md`:

```markdown
# Agent

You are a general-purpose assistant running on the Octant homelab.
```

Environment controls the model routing:
- `ANTHROPIC_BASE_URL=http://litellm.service.consul:4000` — routes SDK to LiteLLM
- `ANTHROPIC_API_KEY` — LiteLLM master key (authenticates to the proxy)
- `ANTHROPIC_MODEL=local/glm-5-fp8` — selects the local model via LiteLLM

## Non-Goals

- Telegram, Discord, or WhatsApp channel support (add later)
- Agent teams/swarms (single agent only)
- Scheduled tasks
- Mount allowlist configuration (agents access only their group folder)
- Multiple agents or model selection per group
- Replacing OpenClaw Gateway (this runs alongside it)

## Validation

1. **Nomad job health:**
   ```bash
   nomad job status bastionclaw
   ```
   Both `orchestrator` and `qmd` tasks should be running.

2. **Consul service registration:**
   ```bash
   consul catalog services | grep bastionclaw
   ```

3. **WebUI accessible:**
   ```bash
   curl -s https://bastionclaw.lab.shamsway.net/ | head
   ```

4. **Agent container spawning** — send a message via WebUI and verify:
   ```bash
   # On a Nomad client node as hashi user:
   podman ps | grep bastionclaw-agent
   ```

5. **LiteLLM routing** — check LiteLLM logs for incoming requests from the agent:
   ```bash
   nomad alloc logs <litellm-alloc-id>
   ```
