# OpenClaw Gateway

AI agent platform deployment for the USS Octant. Runs a single hub agent (Scotty) powered by local LLM inference via LiteLLM/vLLM on the MI300X, with Rocket.Chat as the team chat channel.

**Design doc:** `docs/plans/2026-03-02-openclaw-gateway-design.md`
**Implementation plan:** `docs/plans/2026-03-02-openclaw-gateway-implementation.md`

## Status

Deployed and running. Scotty agent connects to Rocket.Chat (`#bridge` channel) and responds to messages via GLM-5-FP8 running on the local MI300X through the LiteLLM proxy.

- Gateway: `openclaw-gateway` Nomad job (rootless Podman)
- Web UI: `https://openclaw.lab.shamsway.net` (Control UI, paired via token)
- Chat: Rocket.Chat `#bridge` channel, bot user `scotty-bot`
- Model: `litellm/local/glm-5-fp8` → LiteLLM → vLLM (MI300X)

## Architecture

```
Rocket.Chat (rocketchat.lab.shamsway.net)
    ↕ websocket (scotty-bot)
OpenClaw Gateway (Nomad, port 18789)
    ↕ OpenAI-compatible API
LiteLLM Proxy (litellm.service.consul:4000)
    ↕ openai/glm-5-fp8
vLLM (192.168.122.1:8000, MI300X GPU)
```

LiteLLM is required as a proxy between OpenClaw and vLLM. OpenClaw's `openai-completions` API handler strips the `/v1` path prefix from the `baseUrl` when constructing request URLs, causing direct vLLM connections to 404. LiteLLM handles the URL routing correctly.

## 1Password Secrets

The Terraform config references these 1Password items in the `Octant` vault:

| Item | Field | Purpose |
|------|-------|---------|
| `service_openclaw` | `.password` | Gateway HTTP auth token |
| `bot_openclaw_rocketchat` | `.username` / `.password` | Rocket.Chat bot credentials |
| `service_litellm` | `.password` | LiteLLM proxy master key |
| `api_anthropic_key` | `.password` | Anthropic API key |

## Building the Container Image

Option A — via botctl:

```bash
cd ~/git/octant-private/terraform/openclaw-gateway
./botctl --target homelab image build
podman tag openclaw-homelab:latest 192.168.122.1:5000/openclaw-gateway:2026.3.3
podman push 192.168.122.1:5000/openclaw-gateway:2026.3.3
```

Option B — direct build:

```bash
podman build -t openclaw-gateway:latest -f image/Dockerfile.base .
podman tag openclaw-gateway:latest 192.168.122.1:5000/openclaw-gateway:2026.3.3
podman push 192.168.122.1:5000/openclaw-gateway:2026.3.3
```

Update the image tag in `image.auto.tfvars` after pushing.

## Deploying Config Changes

The gateway config (`openclaw.json`) lives on CephFS and is volume-mounted into the container. Terraform does not manage this file directly.

```bash
# Edit the config locally
vi terraform/openclaw-gateway/config/openclaw.json

# Deploy to CephFS
cat terraform/openclaw-gateway/config/openclaw.json | \
  ssh admin@192.168.122.101 "sudo -u hashi tee /mnt/services/openclaw-gateway/config/openclaw.json > /dev/null"

# Restart the allocation to pick up changes
ssh admin@192.168.122.101 'sudo -u hashi nomad alloc restart $(nomad job status openclaw-gateway 2>/dev/null | grep running | awk "{print \$1}")'
```

OpenClaw supports hot-reload for some config changes, but a restart is safest for model provider changes.

## Deploying Infrastructure Changes

For changes to the Nomad job spec, Terraform variables, or 1Password secret bindings:

```bash
cd terraform/openclaw-gateway
terraform plan
terraform apply -auto-approve
```

## Validating

```bash
# Job health
nomad job status openclaw-gateway
consul catalog services | grep openclaw

# Logs (check for "agent model: litellm/local/glm-5-fp8" on startup)
nomad alloc logs -job openclaw-gateway
nomad alloc logs -job openclaw-gateway -stderr

# CLI test from inside the allocation
nomad alloc exec -task openclaw-gateway <alloc-id> \
  node /app/openclaw.mjs agent --local --agent scotty --message "say hello" --json --timeout 30

# Direct LiteLLM test
curl -s -X POST http://litellm.service.consul:4000/v1/chat/completions \
  -H "Authorization: Bearer <litellm-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"local/glm-5-fp8","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'
```

Test via Rocket.Chat by mentioning `@scotty-bot` in the `#bridge` channel.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `404 status code (no body)` | Model provider config — ensure using LiteLLM, not direct vLLM |
| `plugin not found: rocketchat` | Cosmetic warning — the plugin loads via auto-detection from `channels.rocketchat` config |
| Bot doesn't respond in RC | Check `nomad alloc logs` for RC connection errors; verify bot credentials in 1Password |
| Agent responds but no tool use | Check that `api: "openai-completions"` is set, not `anthropic-messages` |

## File Layout

```
terraform/openclaw-gateway/
├── main.tf                          # Terraform config, 1Password secrets
├── variables.tf                     # Cluster-specific variable defaults
├── image.auto.tfvars                # Container image tag
├── openclaw-gateway.nomad.hcl       # Nomad job spec (Podman, rootless)
├── botctl                           # CLI management wrapper
├── botctl.yaml                      # Target configuration for botctl
├── config/
│   ├── openclaw.json                # Gateway runtime config (Scotty team)
│   ├── workspace/                   # Scotty agent workspace files
│   │   ├── IDENTITY.md, SOUL.md, AGENTS.md, TOOLS.md, USER.md
│   ├── teams/knowledge/             # Knowledge team config
│   │   ├── openclaw.json            # Team config overlay
│   │   └── team.md                  # Team documentation
│   └── workspaces/                  # Knowledge team workspace files
│       ├── archivist/               # Hub agent (coordinator)
│       ├── vec-ingest/              # Vector embedding specialist
│       ├── graph-ingest/            # Knowledge graph specialist
│       └── notes-ingest/            # Obsidian vault specialist
├── image/                           # Container image (Dockerfile.base)
├── lib/                             # botctl library scripts
└── README.md                        # This file
```

## CephFS Layout

```
/mnt/services/openclaw-gateway/
├── config/
│   ├── openclaw.json                # Runtime config (volume-mounted as ~/.openclaw/)
│   ├── agents/<id>/                 # Per-agent state (auto-created)
│   │   ├── agent/models.json        # CACHED model config (see troubleshooting)
│   │   └── sessions/                # Session transcripts
│   ├── credentials/rocketchat/      # Bot credentials (auto-created)
│   ├── devices/                     # Control UI pairing tokens
│   ├── memory/                      # Per-agent SQLite memory databases
│   └── identity/                    # Gateway identity
└── workspaces/
    ├── scotty/                      # Scotty workspace
    ├── archivist/                   # Knowledge team hub
    ├── vec-ingest/                  # Knowledge team specialists
    ├── graph-ingest/
    └── notes-ingest/
```

## Multi-Agent Teams

For deploying agent teams beyond the single Scotty agent, see:
- **`docs/guides/openclaw-agent-deployment.md`** — full deployment guide
- **`docs/openclaw-skill-feedback.md`** — lessons learned from knowledge team deployment
- **`docs/plans/2026-03-05-knowledge-layer-test-prompts.md`** — agent test prompts

### Active Teams

| Team | Config | Agents | Model |
|------|--------|--------|-------|
| Scotty (default) | `config/openclaw.json` | scotty | litellm/local/glm-5-fp8 |
| Knowledge | `config/teams/knowledge/openclaw.json` | archivist, vec-ingest, graph-ingest, notes-ingest | litellm/local/minimax-m2.5 |

### Known Issues

- **LiteLLM dynamic port**: Nomad assigns a dynamic port to LiteLLM. The `baseUrl` in openclaw.json must reference the actual port, not the default 4000. See the deployment guide for resolution options.
- **Per-agent model cache**: OpenClaw caches model provider config per-agent at `~/.openclaw/agents/<id>/agent/models.json`. After changing provider URLs, delete these caches or agents will use the stale URL.
- **Rocket.Chat plugin warning**: `plugins.entries.rocketchat` is stale; the plugin auto-loads from `channels.rocketchat` config. Remove from `plugins.entries` to silence the warning.
