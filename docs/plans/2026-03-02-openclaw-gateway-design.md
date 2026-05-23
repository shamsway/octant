# OpenClaw Gateway Deployment — VM Cluster

**Date:** 2026-03-02
**Status:** Approved
**Approach:** Fork-and-adapt from octant-private/terraform/openclaw-gateway

## Summary

Deploy OpenClaw gateway to the octant VM cluster as a demo-ready AI agent platform showcasing AMD MI300X GPU capabilities and local/open-source LLM inference. MVP is a single hub agent (Scotty) on Rocket.Chat (self-hosted), powered by local models via LiteLLM/vLLM.

## Goals

1. **Full AI stack showcase:** Local inference (vLLM) -> agent platform (OpenClaw) -> observability (Phoenix) — all running on local hardware
2. **GPU compute power:** Demonstrate MI300X running frontier-scale open-source models (DeepSeek V3.2, GLM-5, Qwen 3.5)
3. **Demo-ready:** Campy sci-fi crew theme, suitable for technical demos with humor
4. **Extensible:** MVP hub agent first, add monitoring and task agents in phase 2

## Architecture

```
                    Internet
                       |
              nginx (80/443)
                       |
              Traefik (Consul catalog)
                       |
    +------------------+------------------+
    |                  |                  |
openclaw-gateway    LiteLLM           Phoenix
(openclaw.lab.*)   (litellm.lab.*)   (phoenix.lab.*)
    |                  |
    |    Consul DNS    |
    +------------------+
    |
    v
vLLM on hypervisor (192.168.122.1:8000)
    |
    v
MI300X - 1.5TB GPU RAM
+-- DeepSeek V3.2 (671B MoE)
+-- GLM-5-FP8 (existing)
+-- Qwen 3.5 (397B MoE)
+-- MiMo-V2-Flash (lightweight)
```

- OpenClaw gateway runs as rootless Podman container in Nomad
- No node pinning — floats across octant-01/02/03
- LLM routing: OpenClaw -> LiteLLM (Consul DNS) -> vLLM (hypervisor) -> MI300X
- Agent configs stored on CephFS at `/mnt/services/openclaw-gateway/`
- Rocket.Chat as primary channel (self-hosted at `rocketchat.lab.shamsway.net`); CLI and OpenClaw web UI as secondary (post-MVP)
- Observability via existing Phoenix + OpenTelemetry stack

## Agent Roster

Theme: Campy sci-fi starship crew. The MI300X is the ship's reactor core. The cluster is the ship. Think Original Series Trek meets Galaxy Quest.

### Phase 1 (MVP)

| Role | Name | Emoji | Persona |
|------|------|-------|---------|
| Hub / Chief Engineer | Scotty | `🔧` | Chief Engineer of the USS Octant. Obsessed with the "warp core" (MI300X). Speaks in overwrought engineering metaphors. Knows every model, every endpoint, every service. |

### Phase 2

| Role | Name | Emoji | Persona |
|------|------|-------|---------|
| Monitor / Science Officer | Spock | `🖖` | Monitors all systems with Vulcan precision. Reports anomalies with deadpan understatement. Never panics. Always has the data. |
| Task Runner / Helmsman | Sulu | `🚀` | Executes maintenance with enthusiasm. Treats every routine task like a precision docking sequence. |

## LLM Backend & Model Routing

vLLM multi-model on hypervisor, LiteLLM in cluster as routing proxy. OpenClaw talks to LiteLLM via Consul DNS — never directly to vLLM.

### Model Roster

| Model | Role | Demo Narrative |
|-------|------|----------------|
| `local/deepseek-v3.2` | Primary reasoning & code | #1 open-source, SWE-Bench leader, 671B MoE |
| `local/glm-5-fp8` | Fast general / coding | Already running, proven |
| `local/qwen-3.5` | Agentic tasks, long context | 262K native context, designed for agents |
| `local/mimo-v2-flash` | Lightweight fast tasks | Sub-second for simple queries |

Note: Exact model selection and concurrency depends on what fits in GPU memory. Models won't all run simultaneously — vLLM config determines which are loaded.

### LiteLLM Config Additions

```yaml
model_list:
  - model_name: local/deepseek-v3.2
    litellm_params:
      model: openai/deepseek-ai/DeepSeek-V3.2
      api_base: http://192.168.122.1:8000/v1
      api_key: "no-key-required"
  - model_name: local/glm-5-fp8
    litellm_params:
      model: openai/glm-5-fp8
      api_base: http://192.168.122.1:8000/v1
      api_key: "no-key-required"
  - model_name: local/qwen-3.5
    litellm_params:
      model: openai/Qwen/Qwen3.5-397B-A17B
      api_base: http://192.168.122.1:8000/v1
      api_key: "no-key-required"
  - model_name: local/mimo-v2-flash
    litellm_params:
      model: openai/mimo-v2-flash
      api_base: http://192.168.122.1:8000/v1
      api_key: "no-key-required"
```

### OpenClaw Model Config

- Default: `local/deepseek-v3.2`
- Fallback chain: `local/glm-5-fp8` -> `local/qwen-3.5` -> `local/mimo-v2-flash`

Model names are placeholders — exact HuggingFace IDs depend on what vLLM serves.

## Terraform & Nomad Deployment

### Cluster Differences from Personal Deployment

| Aspect | Personal (octant-private) | VM Cluster (this repo) |
|--------|--------------------------|------------------------|
| Datacenter | `shamsway` | `octant` |
| Domain | `shamsway.net` | `lab.shamsway.net` |
| DNS servers | `192.168.252.1/6/7` | `192.168.122.101/102/103` |
| Node constraint | Pinned to `jerry-agent` | No pin — floats across cluster |
| LLM backend | ZAI (api.z.ai) | LiteLLM -> vLLM (hypervisor) |
| Image registry | `registry.service.consul:8082` | `192.168.122.1:5000` (local) |
| Secrets | ZAI, Moonshot, Slack, Discord, OP | Rocket.Chat, OP, LiteLLM |
| Resources | 1024 CPU / 4092 MB | Same (adjust after testing) |

### Files in `terraform/openclaw-gateway/`

1. **`openclaw-gateway.nomad.hcl`** — Adapted Nomad job spec, no node pin, octant DNS/env
2. **`main.tf`** — 1Password + Nomad providers, secrets, `templatefile()` (not deprecated `data.template_file`)
3. **`variables.tf`** — Standard octant defaults

### Secrets (1Password -> Nomad Variables)

| 1Password Item | Env Var | Purpose |
|----------------|---------|---------|
| `service_openclaw` | `OPENCLAW_GATEWAY_TOKEN` | Gateway HTTP auth |
| `bot_openclaw_rocketchat` | `ROCKETCHAT_BOT_USER`, `ROCKETCHAT_BOT_PASSWORD` | Rocket.Chat bot credentials |
| `service_litellm` | `LITELLM_API_KEY` | LiteLLM proxy auth |
| `api_anthropic_key` | `ANTHROPIC_API_KEY` | Fallback if needed |

### Volume Mounts

```
/mnt/services/openclaw-gateway/config     -> /home/node/.openclaw
/mnt/services/openclaw-gateway/workspaces -> /home/node/.openclaw/workspace
```

Volumes already provisioned in `inventory/groups.yml`. Workspace layout is flat for MVP (single agent). Per-agent workspace mounts added in phase 2.

### Consul Service

`openclaw-gateway` at `openclaw.lab.shamsway.net` via Traefik with consulcatalog discovery.

## Scotty — MVP Agent Configuration

### Gateway Config (`openclaw.json`)

```jsonc
{
  "gateway": {
    "port": 18789,
    "bind": "lan",
    "token": "${OPENCLAW_GATEWAY_TOKEN}",
    "customBindHost": "0.0.0.0"
  },
  "llm": {
    "providers": [{
      "id": "litellm",
      "api": "anthropic-messages",
      "baseUrl": "http://litellm.service.consul:4000"
    }],
    "default": "local/deepseek-v3.2",
    "fallback": ["local/glm-5-fp8", "local/qwen-3.5"]
  },
  "agents": {
    "list": [{
      "id": "scotty",
      "default": true,
      "workspace": "/home/node/.openclaw/workspace"
    }]
  },
  "plugins": {
    "rocketchat": { "enabled": true },
    "memory-core": { "enabled": true },
    "lobster": { "enabled": true },
    "llm-task": { "enabled": true },
    "diagnostics-otel": { "enabled": true }
  },
  "session": {
    "maintenance": {
      "mode": "enforce",
      "pruneAfter": "30d",
      "maxEntries": 500,
      "rotateBytes": "10mb"
    }
  }
}
```

### Workspace Files

Following AGENT_BEST_PRACTICES.md conventions:

- **IDENTITY.md** — Name, emoji, one-liner
- **SOUL.md** — First-person campy sci-fi engineer character, values, boundaries
- **AGENTS.md** — Startup sequence (SOUL.md -> USER.md -> TOOLS.md -> MEMORY.md), operating rules, demo awareness
- **TOOLS.md** — MCP endpoints (nomad-mcp, infra-mcp), LiteLLM, Consul, Nomad, model inventory with personality notes
- **USER.md** — Demo context, audience description, Matt as captain

### Tool Policy

```jsonc
{
  "profile": "coding",
  "alsoAllow": ["group:web", "group:sessions", "memory_search", "memory_get",
                "message", "agents_list", "lobster", "llm-task"],
  "deny": ["image", "browser", "canvas", "cron", "gateway", "nodes"]
}
```

### Key Persona Principle

Camp lives in SOUL.md (character). Operational rules stay serious in AGENTS.md. Humor does not leak into safety constraints or monitoring thresholds.

## Image Strategy & Operational Tooling

### Container Image

- Same two-stage build as personal deployment (base + infra Dockerfiles)
- Push to local registry: `192.168.122.1:5000/openclaw-gateway:latest`
- Build from OpenClaw source via botctl

### botctl Target

```yaml
vm-cluster:
  driver: nomad
  openclaw:
    nomad_job: openclaw-gateway
    image:
      name: openclaw-gateway
      registry: 192.168.122.1:5000
    github_url: https://github.com/openclaw/openclaw
    github_ref: main
    agents: [scotty]
  storage:
    agents_repo: ~/git/openclaw-agents
    ceph_base: /mnt/services/openclaw-gateway
```

Provides `botctl --target vm-cluster gateway status`, `config deploy`, `image build` from day one.

## Phase 2 Roadmap

After MVP is validated:

1. Add Spock (monitor) + Sulu (task runner) agents with per-agent workspace mounts
2. Cron jobs for heartbeats and maintenance tasks
3. OpenClaw web UI channel
4. CLI access
5. Knowledge layer integration (Qdrant, Graphiti, Phoenix)
6. Model benchmarking and comparison demos
7. Multi-agent orchestration demos

## References

- Personal deployment: `~/git/octant-private/terraform/openclaw-gateway/`
- Agent configs: `~/git/openclaw-agents/`
- Agent best practices: `~/git/openclaw-agents/docs/AGENT_BEST_PRACTICES.md`
- Existing LiteLLM: `terraform/litellm/`
- Existing BastionClaw: `terraform/bastionclaw/`
