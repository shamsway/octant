# Deploying OpenClaw Agent Teams on Nomad

Guide for deploying multi-agent teams to the OpenClaw gateway on the Octant homelab. Covers the full lifecycle from workspace authoring through CephFS deployment, Nomad volume mounting, config management, and agent validation.

**Related docs:**
- `docs/guides/openclaw-rocketchat-integration.md` — Rocketchat bot accounts, credentials, DM/group setup
- `terraform/rocketchat/NOTES.md` — Rocketchat deployment, DB reset recovery
- `terraform/openclaw-gateway/README.md` — single-agent (Scotty) deployment
- `docs/plans/2026-03-02-openclaw-gateway-design.md` — gateway architecture
- OpenClaw skills: `openclaw-agent-creator`, `openclaw-agent-manager`, `openclaw-provider-manager`

---

## Architecture

```
Repo (source of truth)                    CephFS (runtime)
─────────────────────                    ────────────────
config/teams/<team>/                     /mnt/services/openclaw-gateway/
├── openclaw.json    ──── deploy ────>   ├── config/openclaw.json
├── team.md                              │   ├── agents/<id>/agent/models.json  (auto-cached)
└── workspaces/                          │   └── agents/<id>/sessions/          (auto-created)
    ├── archivist/   ──── scp ────────>  └── workspaces/<id>/
    │   ├── SOUL.md                          ├── SOUL.md
    │   ├── TOOLS.md                         ├── TOOLS.md
    │   └── ...                              ├── .openclaw/                     (auto-created)
    └── vec-ingest/  ──── scp ────────>      └── memory/                       (auto-created)
```

The gateway reads `openclaw.json` from `/mnt/services/openclaw-gateway/config/` and agent workspaces from volume-mounted paths defined in the Nomad HCL.

---

## Step 1: Design the Team

Create `config/teams/<team-name>/team.md` documenting:

| Field | Example |
|-------|---------|
| Team name | `knowledge` |
| Purpose | Ingest, index, retrieve knowledge across vector/graph/note backends |
| Hub agent | Archivist (coordinator) |
| Specialist agents | Vec-Ingest, Graph-Ingest, Notes-Ingest |
| Model requirements | Inference: minimax-m2.5, Embedding: bge-large-en-v1.5 |
| Dependencies | Qdrant, Graphiti, LiteLLM, Obsidian vault (CephFS) |
| Inter-agent contracts | JSON request/response stubs per specialist |

Use the `openclaw-agent-creator` skill for each agent to produce workspace files.

---

## Step 2: Author Workspace Files

Each agent needs a workspace directory in the repo at `config/workspaces/<agent-id>/`:

```
config/workspaces/<agent-id>/
├── SOUL.md        # Identity, values, boundaries (first person)
├── IDENTITY.md    # Name, emoji, vibe
├── AGENTS.md      # Startup sequence, operating model, contracts, safety rules
├── TOOLS.md       # Tool inventory, API endpoints, lessons learned
├── USER.md        # User context (shared across agents)
├── HEARTBEAT.md   # Scheduled checks or on-demand stub
└── HANDOFFS.md    # Delegation contracts (hub agents only)
```

**Rules:**
- `SOUL.md` is identity, not operations. Write in first person.
- `AGENTS.md` is operations, not identity. Define the startup read sequence.
- `TOOLS.md` lists API endpoints with actual hostnames (`qdrant.service.consul:6333`).
- `HEARTBEAT.md` must have concrete check IDs, intervals, and success criteria.
- `USER.md` can be copied from the hub agent's workspace.

---

## Step 3: Write the Team Config

Create `config/teams/<team-name>/openclaw.json`:

```jsonc
{
  "models": {
    "mode": "merge",
    "providers": {
      "litellm": {
        // Use the Traefik HTTPS URL to avoid LiteLLM dynamic port issues
        "baseUrl": "https://litellm.lab.shamsway.net/v1",
        "apiKey": "your-litellm-key",
        "api": "openai-completions",
        "models": [
          {
            "id": "local/model-name",
            "name": "Display Name",
            "reasoning": true,             // true for thinking models
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 1048576,
            "maxTokens": 131072
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "litellm/local/model-name"
      },
      "workspace": "/home/node/.openclaw/workspace",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 4 },
      // Optional: embedding for vector memory
      "memorySearch": {
        "provider": "openai",
        "model": "bge-large-en-v1.5",
        "remote": {
          "baseUrl": "http://192.168.122.1:8001/v1",
          "apiKey": "no-key-required"
        }
      }
    },
    "list": [
      {
        "id": "hub-agent",
        "default": true,
        "workspace": "/home/node/.openclaw/workspaces/hub-agent",
        "identity": { "name": "Hub Agent", "emoji": "📚" },
        "tools": {
          "allow": [
            "exec", "read", "write", "edit",
            "group:web", "group:sessions",
            "memory_search", "memory_get", "message",
            "agents_list", "lobster", "llm-task"
          ]
        }
      },
      {
        "id": "specialist",
        "workspace": "/home/node/.openclaw/workspaces/specialist",
        "identity": { "name": "Specialist", "emoji": "🔧" },
        "tools": {
          "allow": ["exec", "memory_get", "memory_search", "message"]
        }
      }
    ]
  },
  "tools": {
    "deny": ["apply_patch", "cron", "gateway", "nodes"],
    "exec": { "applyPatch": { "enabled": false } }
  },
  // Bindings connect agents to Rocketchat rooms/DMs.
  // See docs/guides/openclaw-rocketchat-integration.md for full details.
  "bindings": [
    {
      "agentId": "hub-agent",
      "match": {
        "channel": "rocketchat",
        "accountId": "hub-agent",
        "peer": { "kind": "channel", "id": "bridge" }
      }
    }
  ],
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  // Rocketchat channel config. Bot accounts, groups, and DM policy.
  // See docs/guides/openclaw-rocketchat-integration.md for full details.
  "channels": {
    "rocketchat": {
      "enabled": true,
      "serverUrl": "https://rocketchat.lab.shamsway.net",
      "dmPolicy": "pairing",
      "accounts": {
        "hub-agent": {
          "botUsername": "hub-agent-bot",
          "botDisplayName": "Hub Agent"
        }
      },
      "groups": {
        "bridge": {
          "bots": ["hub-agent-bot"]
        }
      }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "custom",
    "customBindHost": "0.0.0.0",
    "controlUi": {
      "allowedOrigins": ["https://openclaw.lab.shamsway.net"]
    },
    "channelHealthCheckMinutes": 5,
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}",
      "rateLimit": {
        "maxAttempts": 10,
        "windowMs": 60000,
        "lockoutMs": 300000,
        "exemptLoopback": true
      }
    },
    "http": {
      "endpoints": {
        "chatCompletions": { "enabled": false },
        "responses": { "enabled": false }
      }
    },
    "tailscale": { "mode": "off", "resetOnExit": false }
  },
  "plugins": {
    "slots": { "memory": "memory-core" },
    "entries": {
      "openclaw-rocketchat": { "enabled": true },  // Required for Rocketchat
      "memory-core": { "enabled": true },
      "lobster": { "enabled": true },
      "llm-task": {
        "enabled": true,
        "config": {
          "defaultProvider": "litellm",
          "defaultModel": "local/model-name",
          "maxTokens": 2048,
          "timeoutMs": 30000
        }
      },
      "diagnostics-otel": { "enabled": true }
    }
  },
  "diagnostics": {
    "enabled": true,
    "otel": {
      "enabled": true,
      "endpoint": "http://otel-collector.service.consul:4328",
      "protocol": "http/protobuf",
      "serviceName": "openclaw-gateway",
      "traces": true,
      "metrics": false,
      "logs": false,
      "sampleRate": 1.0,
      "flushIntervalMs": 10000
    }
  },
  "discovery": { "mdns": { "mode": "off" } },
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

### Tool Policy Decision

| Agent Type | Pattern | Notes |
|------------|---------|-------|
| Hub/orchestrator | Explicit `allow` list | List all needed tools; avoids profile bloat |
| Specialist (needs exec) | `allow: ["exec", "memory_get", "memory_search", "message"]` | Minimal set |
| Specialist (file-only) | `allow: ["exec", "write", "edit", "read", "message"]` | No memory tools |

**Avoid `profile: "coding"`** for local model deployments — the profile expands to a large tool schema that increases prompt size and inference time. Use explicit `allow` lists instead.

### Tool Name Validation

Not all tool names work in `allow` lists. After deploying, check stderr for:
```
agents.<id>.tools.allow allowlist contains unknown entries (<name>)
```

Known invalid names: `glob`, `grep` (profile-internal, not standalone IDs).

---

## Step 4: Create CephFS Volumes

Add volume entries to `inventory/groups.yml` under the `volumes` list:

```yaml
# Agent workspaces
- name: openclaw-gateway-<agent-id>-workspace
  path: /mnt/services/openclaw-gateway/workspaces/<agent-id>
  backup: true
- name: openclaw-gateway-<agent-id>-memory
  path: /mnt/services/openclaw-gateway/workspaces/<agent-id>/memory
  backup: true

# External mounts (if needed)
- name: obsidian-vault
  path: /mnt/services/obsidian/vault
  backup: true
```

Run the volumes playbook:
```bash
ansible-playbook playbooks/05-deploy-volumes.yml \
  -i inventory/provisioned_vms.yml -i inventory/groups.yml
```

**Do NOT use `make deploy-role ROLE=volumes`** — the volumes role is not in `octant.yml`.

---

## Step 5: Add Volume Mounts to Nomad HCL

Edit `openclaw-gateway.nomad.hcl` to add volume mounts for each agent workspace:

```hcl
volumes = [
  "/mnt/services/openclaw-gateway/config:/home/node/.openclaw",
  # Hub agent workspace
  "/mnt/services/openclaw-gateway/workspaces/<hub-id>:/home/node/.openclaw/workspaces/<hub-id>",
  # Specialist workspaces
  "/mnt/services/openclaw-gateway/workspaces/<spec-1>:/home/node/.openclaw/workspaces/<spec-1>",
  "/mnt/services/openclaw-gateway/workspaces/<spec-2>:/home/node/.openclaw/workspaces/<spec-2>",
  # External mounts
  "/mnt/services/obsidian/vault:/mnt/services/obsidian/vault",
]
```

Apply the Nomad job:
```bash
cd terraform/openclaw-gateway
terraform plan
terraform apply -auto-approve
```

---

## Step 6: Deploy Workspace Files

SCP workspace files from the repo to CephFS:

```bash
for agent in archivist vec-ingest graph-ingest notes-ingest; do
  scp config/workspaces/$agent/*.md \
    octant-01:/mnt/services/openclaw-gateway/workspaces/$agent/
done
```

**Note:** The `hashi` user needs write access to these directories. If using `admin` user, prefix with `sudo -u hashi`.

---

## Step 7: Deploy Config

### Switching teams

When switching from one team config to another (e.g., Scotty → Knowledge):

1. Back up the current config:
   ```bash
   ssh octant-01 'cp /mnt/services/openclaw-gateway/config/openclaw.json \
     /mnt/services/openclaw-gateway/config/openclaw.json.previous-team'
   ```

2. Deploy the new team config:
   ```bash
   scp config/teams/knowledge/openclaw.json \
     octant-01:/mnt/services/openclaw-gateway/config/openclaw.json
   ```

3. Restart the gateway (team switches require restart due to channel/plugin changes):
   ```bash
   ALLOC=$(ssh octant-01 'nomad job status openclaw-gateway | grep running | awk "{print \$1}"')
   ssh octant-01 "nomad alloc restart $ALLOC"
   ```

### LiteLLM URL

Use the Traefik HTTPS URL (`https://litellm.lab.shamsway.net/v1`) instead of the Consul
internal address. This avoids the dynamic port problem entirely — LiteLLM runs on a
Nomad-assigned dynamic port, so `litellm.service.consul:4000` is unreliable.

If you need the internal address (e.g., for testing from inside the container), resolve
the current port via Consul:
```bash
ssh octant-01 'curl -s http://localhost:8500/v1/catalog/service/litellm | \
  python3 -c "import sys,json; s=json.load(sys.stdin)[0]; print(f\"{s[\"ServiceAddress\"]}:{s[\"ServicePort\"]}\")"'
```

---

## Step 8: Validate

### Gateway health
```bash
# Job status
nomad job status openclaw-gateway

# Gateway logs (check for startup errors)
ALLOC=$(ssh octant-01 'nomad job status openclaw-gateway | grep running | awk "{print \$1}"')
ssh octant-01 "nomad alloc logs -stderr $ALLOC" | tail -20

# Gateway status
ssh octant-01 "nomad alloc exec $ALLOC node openclaw.mjs gateway status"
```

**Check the Memory line** for `vector ready` (if memorySearch is configured) vs `vector unknown`.

### Agent orientation

Send a basic prompt to each agent to verify it can read its workspace files and identify its tools:

```bash
ssh octant-01 "nomad alloc exec $ALLOC node openclaw.mjs agent \
  --agent <agent-id> \
  --message 'Read your SOUL.md and TOOLS.md. Who are you? What tools do you have access to? Reply briefly.' \
  --timeout 300"
```

Run this for every agent in the team. Expected: each agent identifies itself by name and lists its available tools/APIs.

### Direct LLM test

If agents time out, test the LLM endpoint directly from inside the container:

```bash
ssh octant-01 "nomad alloc exec $ALLOC node -e \"
const http = require('http');
const body = JSON.stringify({model:'local/minimax-m2.5',messages:[{role:'user',content:'Say hello'}],max_tokens:20});
const req = http.request({hostname:'192.168.122.101',port:25844,path:'/v1/chat/completions',method:'POST',
  headers:{'Content-Type':'application/json','Authorization':'Bearer YOUR_KEY','Content-Length':body.length}},
  res=>{let d='';res.on('data',c=>d+=c);res.on('end',()=>console.log(d));});
req.write(body);req.end();\""
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| All agents: "LLM request timed out" | LiteLLM URL/port wrong in config | Use Traefik HTTPS URL (`https://litellm.lab.shamsway.net/v1`); or resolve actual port via Consul API |
| One agent times out, others work | Stale `models.json` cache | Delete `~/.openclaw/agents/<id>/agent/models.json` |
| "Unknown config keys" crash | Unsupported config field | Remove the field; run `openclaw doctor` for suggestions |
| "plugin not found: rocketchat" | Wrong name in `plugins.entries` | Use `"openclaw-rocketchat"` (not `"rocketchat"`) |
| Agent responds but no tool calls | Wrong API type | Ensure `"api": "openai-completions"` for OpenAI-compatible endpoints |
| "allowlist contains unknown entries" | Invalid tool name in `allow` list | Remove the tool name; use `group:*` or valid individual names |
| "config change requires gateway restart" | Channel/plugin config changed | Restart the allocation: `nomad alloc restart <alloc-id>` |
| Gateway moved to different node | Nomad rescheduled after crash/restart | Re-resolve allocation: `nomad job status openclaw-gateway` |
| memorySearch shows "vector unknown" | No `memorySearch` config | Add `agents.defaults.memorySearch` block with embedding endpoint |
| Rocketchat: bot not responding | Missing groups/bindings/credentials | See `docs/guides/openclaw-rocketchat-integration.md` troubleshooting |

### Clearing Per-Agent State

When an agent is stuck in a bad state:

```bash
# Clear session history
rm -rf ~/.openclaw/agents/<agent-id>/sessions/*

# Clear cached model config (IMPORTANT after provider URL changes)
rm ~/.openclaw/agents/<agent-id>/agent/models.json

# Clear memory database
rm ~/.openclaw/memory/<agent-id>.sqlite
```

All paths are relative to `/mnt/services/openclaw-gateway/config/` on CephFS (which maps to `/home/node/.openclaw/` inside the container).

---

## Config Management

### Hot-reload vs restart

| Change Type | Reload Method |
|-------------|--------------|
| Agent list (add/remove/modify) | Hot-reload (automatic) |
| Model providers (URL, key, models) | Hot-reload (but clear agent model caches!) |
| Tool policy changes | Hot-reload |
| Channel integrations | **Requires restart** |
| Plugin enable/disable | **Requires restart** |
| Gateway settings (port, auth) | **Requires restart** |

### Config drift

The deployed config on CephFS may drift from the repo copy due to:
- Gateway CLI changes applied via hot-reload
- Per-agent `models.json` caches overriding provider URLs
- `openclaw doctor --fix` auto-migrations (can break Rocketchat accounts — see
  `docs/guides/openclaw-rocketchat-integration.md` for details)

After making changes, always verify the deployed config:
```bash
ssh octant-01 "nomad alloc exec $ALLOC cat /home/node/.openclaw/openclaw.json" | python3 -m json.tool
```

### botctl

The `botctl` CLI wrapper at `terraform/openclaw-gateway/botctl` provides shortcuts:

```bash
./botctl gateway status    # Gateway health + model status
./botctl gateway logs      # Stdout logs
./botctl gateway logs-err  # Stderr logs
./botctl gateway restart   # Restart allocation
./botctl config deploy     # Deploy config to CephFS
```

Requires `botctl.yaml` configuration (see `botctl.yaml.example`).

---

## Checklist: New Agent Team Deployment

```
Pre-deployment:
- [ ] Team doc written (config/teams/<team>/team.md)
- [ ] All workspace files authored and reviewed
- [ ] Team openclaw.json validated (no unknown config keys)
- [ ] LiteLLM model available and tested via curl
- [ ] Embedding model running (if memorySearch needed)

Infrastructure:
- [ ] CephFS volumes added to inventory/groups.yml
- [ ] Ansible volumes playbook run successfully
- [ ] Nomad HCL updated with volume mounts
- [ ] Terraform applied (new allocation started)

Rocketchat (if connecting agents — see docs/guides/openclaw-rocketchat-integration.md):
- [ ] Bot user(s) created in Rocketchat (role: bot)
- [ ] Private group(s) created (NOT public channels)
- [ ] Bot(s) invited to group(s)
- [ ] API credentials obtained (form-encoded login)
- [ ] bots.json updated on CephFS
- [ ] Accounts, groups, and bindings added to openclaw.json
- [ ] openclaw-rocketchat plugin enabled in plugins.entries

Deployment:
- [ ] Workspace files deployed to CephFS
- [ ] Previous config backed up
- [ ] Team config deployed to CephFS
- [ ] LiteLLM baseUrl uses HTTPS Traefik URL
- [ ] Gateway restarted (channel/plugin changes require restart)

Validation:
- [ ] No startup errors in stderr logs
- [ ] Gateway status shows expected agents
- [ ] memorySearch shows "vector ready" (if configured)
- [ ] Each agent responds to orientation prompt
- [ ] No stale models.json caches from previous team
- [ ] Rocketchat bots show "已连接" and "已订阅房间" in logs (if configured)
```
