# OpenClaw Skill Feedback: Knowledge Layer Agent Deployment Session

**Date**: 2026-03-06
**Task**: Deploy and orient 4-agent knowledge team (Archivist, Vec-Ingest, Graph-Ingest, Notes-Ingest)
**Skills used**: `openclaw-provider-manager`, `openclaw-agent-creator` (reference), `openclaw-agent-manager` (reference), `openclaw` (reference)

---

## Session Summary

Deployed the knowledge team agents to the OpenClaw gateway running on Nomad. Tasks included: updating LiteLLM with a new inference model (minimax-m2.5) and embedding model (bge-large-en-v1.5), configuring the openclaw.json provider and memorySearch blocks, deploying workspace files to CephFS, and running orientation prompts against all 4 agents via `nomad alloc exec`.

---

## Issues Encountered (in order)

| # | Issue | Root Cause | Severity |
|---|-------|-----------|----------|
| 1 | `cron.jobs` config crashed gateway on startup | `cron.jobs` key not supported in current OpenClaw version; config validation rejects unknown keys | High |
| 2 | LiteLLM URL hardcoded to port 4000 but dynamic port is 25844 | Nomad assigns dynamic ports to services; `litellm.service.consul:4000` is wrong — Consul DNS resolves the address but NOT the port | High |
| 3 | All agents returned "LLM request timed out" initially | LiteLLM port mismatch (see #2); requests to port 4000 went nowhere | High |
| 4 | `openclaw agent` CLI requires device pairing | New CLI clients must be approved via `openclaw devices approve` before connecting to a remote gateway | Medium |
| 5 | Archivist agent kept timing out after LiteLLM URL was fixed | **Stale per-agent `models.json` cache** at `~/.openclaw/agents/archivist/agent/models.json` had the old URL cached; overrides main config | **Critical** |
| 6 | `requestTimeout` / `timeout` config keys rejected | No such keys exist at provider or model level in openclaw.json schema | Low |
| 7 | `coding` profile tool warning: `apply_patch` unknown | The `coding` profile references `apply_patch` which may not be available in all OpenClaw versions | Low |
| 8 | `glob`, `grep` tool names in explicit allow list warned as unknown | These are profile-internal names, not available as standalone tool IDs in allow lists | Medium |
| 9 | `rocketchat` plugin not found warning on every startup | Stale `plugins.entries.rocketchat` in config; plugin auto-loads from channel config, not plugin entries | Low |
| 10 | Rocket.Chat connection fails: `Unexpected token '<'` | Rocket.Chat returning HTML instead of JSON — likely auth failure or wrong endpoint | Medium |
| 11 | `memorySearch` showed `vector unknown` | No embedding endpoint configured; needed `agents.defaults.memorySearch` block with OpenAI-compatible embedding provider | Medium |
| 12 | Gateway restarted and moved nodes after config change | Nomad rescheduled allocation to different node (octant-02 → octant-03) after crash loop | Low |

---

## Recommended Skill Updates

### 1. `openclaw-provider-manager/SKILL.md` — Add per-agent model cache warning

The skill covers provider config in `openclaw.json` but does not mention that OpenClaw caches a **per-agent `models.json`** file. When a provider's URL changes, the cached file retains the old URL and silently overrides the main config. This was the root cause of a multi-hour debugging session.

**Add after the "Common Mistakes" section:**

```markdown
## Per-Agent Model Cache (`models.json`)

OpenClaw caches resolved provider config per-agent at:

```
~/.openclaw/agents/<agent-id>/agent/models.json
```

**Critical**: When you change a provider's `baseUrl` or other connection details in
`openclaw.json`, the per-agent cache may retain the OLD values. The agent will
silently use the cached URL, causing "LLM request timed out" errors even though
the main config is correct.

**Symptoms:**
- One agent times out while others (with newer caches) work fine
- Direct endpoint tests succeed but the specific agent can't reach the provider
- The gateway logs show timeouts within 1-2 seconds of agent start

**Fix:**
```bash
# Delete the stale cache for a specific agent
rm ~/.openclaw/agents/<agent-id>/agent/models.json

# Or delete all agent model caches (nuclear option)
find ~/.openclaw/agents -name models.json -path '*/agent/*' -delete
```

**Prevention:** After changing provider URLs, always clear model caches:
```bash
find ~/.openclaw/agents -name models.json -path '*/agent/*' -delete
```

Add this to your post-provider-change checklist alongside `openclaw models status --probe`.
```

---

### 2. `openclaw-provider-manager/SKILL.md` — Add LiteLLM dynamic port gotcha

The LiteLLM provider template uses `"baseUrl": "${LITELLM_BASE_URL}"` but doesn't warn about Nomad's dynamic port assignment. Add to the "LiteLLM Proxy" section:

```markdown
### LiteLLM on Nomad (Dynamic Ports)

When LiteLLM runs as a Nomad service with a dynamic port, `litellm.service.consul`
resolves to the correct IP but Consul DNS does NOT include the port in A records.

**Problem:** `http://litellm.service.consul:4000/v1` will fail because the actual
port is Nomad-assigned (e.g., 25844).

**Solutions (in order of preference):**

1. **Static port in Nomad job** — Pin LiteLLM to a fixed port:
   ```hcl
   network {
     port "http" {
       static = 4000
       to     = 4000
     }
   }
   ```

2. **Consul API lookup** — Query the actual port at runtime:
   ```bash
   curl -s http://localhost:8500/v1/catalog/service/litellm | \
     jq -r '.[0] | "\(.ServiceAddress):\(.ServicePort)"'
   ```

3. **Environment variable** — Set `LITELLM_BASE_URL` in the gateway's Nomad job
   using a Consul template that resolves the port dynamically:
   ```hcl
   template {
     data = <<EOT
   {{ range service "litellm" -}}
   LITELLM_BASE_URL=http://{{ .Address }}:{{ .Port }}/v1
   {{- end }}
   EOT
   }
   ```

Option 3 is the best long-term fix for containerized gateways.
```

---

### 3. `openclaw-provider-manager/SKILL.md` — Add `memorySearch` configuration

The skill covers model providers and routing but does not document the `memorySearch` config block, which is required for vector memory (embedding-based search). Without it, `openclaw gateway status` shows `vector unknown`.

**Add as a new section after "Per-Agent Model Routing":**

```markdown
## Memory Search (Embedding) Configuration

To enable vector-based memory search, configure an embedding endpoint in
`agents.defaults.memorySearch`. This is separate from LLM model routing — it
configures the embedding model used for memory indexing and retrieval.

```json
"agents": {
  "defaults": {
    "memorySearch": {
      "provider": "openai",
      "model": "bge-large-en-v1.5",
      "remote": {
        "baseUrl": "http://192.168.122.1:8001/v1",
        "apiKey": "no-key-required"
      }
    }
  }
}
```

**Fields:**
- `provider`: Always `"openai"` for OpenAI-compatible embedding endpoints
- `model`: The embedding model name as served by the endpoint
- `remote.baseUrl`: The embedding API endpoint (must serve `/embeddings`)
- `remote.apiKey`: API key (use `"no-key-required"` for local servers)

**Validation:** After configuring, check `openclaw gateway status`. The Memory
line should show `vector ready` instead of `vector unknown`.

**Note:** This is NOT the same as adding an embedding model to `models.providers`.
The `memorySearch` block configures the memory plugin's embedding pipeline, which
is independent of the chat model provider chain.
```

---

### 4. `openclaw-agent-manager/SKILL.md` — Add Nomad/homelab deployment patterns

The skill is written for the `openclaw-agents` repo with a flat directory layout. It doesn't cover the homelab pattern where agents are deployed to CephFS via Nomad volume mounts. This is a significant gap for the Octant deployment.

**Add a new section "Homelab Deployment (Nomad + CephFS)":**

```markdown
## Homelab Deployment (Nomad + CephFS)

When agents run inside a Nomad-managed container, workspace files live on CephFS
and are volume-mounted into the container. The deployment flow differs from the
openclaw-agents repo pattern.

### Directory Layout

**In the repo (source of truth):**
```
terraform/openclaw-gateway/config/
├── openclaw.json                    # Main gateway config (Scotty)
├── teams/<team>/
│   ├── openclaw.json                # Team-specific config overlay
│   └── team.md                      # Team documentation
└── workspaces/<agent-id>/           # Per-agent workspace files
    ├── SOUL.md
    ├── AGENTS.md
    ├── TOOLS.md
    └── ...
```

**On CephFS (runtime):**
```
/mnt/services/openclaw-gateway/
├── config/
│   ├── openclaw.json                # Deployed config (may differ from repo)
│   └── agents/<agent-id>/           # Auto-created agent state
│       ├── sessions/                # Session transcripts
│       └── agent/
│           └── models.json          # CACHED model config (see warning below)
└── workspaces/<agent-id>/           # Deployed workspace files
    ├── .openclaw/                   # Auto-created workspace state
    ├── memory/                      # Agent memory
    ├── SOUL.md
    └── ...
```

### Volume Mounts in Nomad HCL

Each agent workspace needs a volume mount in the Nomad job spec:
```hcl
volumes = [
  "/mnt/services/openclaw-gateway/config:/home/node/.openclaw",
  "/mnt/services/openclaw-gateway/workspaces/<agent-id>:/home/node/.openclaw/workspaces/<agent-id>",
]
```

### Deployment Workflow

1. **Create CephFS directories** (via Ansible volumes role)
2. **Deploy workspace files** (SCP from repo to CephFS)
3. **Deploy openclaw.json** (SCP or direct edit on CephFS)
4. **Apply Nomad job** (terraform apply for volume mount changes)
5. **Restart allocation** if needed for config changes

### Config Drift Warning

The deployed config on CephFS may drift from the repo copy due to:
- Hot-reload changes made via gateway CLI
- Per-agent `models.json` caches (see Provider Manager feedback)
- Gateway-generated state files

Always verify the deployed config matches expectations after changes.
```

---

### 5. `openclaw-agent-creator/SKILL.md` — Add `allow` list tool name caveats

The skill's Step 3 (Tool Policy) says restricted agents use a strict `allow` list, but doesn't clarify which tool names are valid in allow lists vs. which are profile-internal.

**Add to the Tool Policy section or to `references/tool-policy.md`:**

```markdown
### Valid Tool Names in `allow` Lists

Not all tool names that appear in profile descriptions are valid in explicit
`allow` lists. Some names are profile-internal and not exposed as standalone tools.

**Known valid names:**
- `exec`, `read`, `write`, `edit`, `apply_patch`
- `web_search`, `web_fetch`
- `memory_search`, `memory_get`
- `message`, `agents_list`
- `sessions_list`, `sessions_history`, `sessions_send`, `sessions_spawn`, `session_status`
- `browser`, `canvas`, `image`
- `cron`, `gateway`, `nodes`
- `lobster`, `llm-task` (plugin-provided)

**Groups (expand to multiple tools):**
- `group:web`, `group:sessions`, `group:runtime`, `group:fs`, `group:ui`,
  `group:automation`, `group:messaging`

**Known INVALID in allow lists:**
- `glob`, `grep` — these are NOT standalone tool IDs; use `group:fs` or individual
  file tools instead
- `apply_patch` — may not be available in all versions; check gateway startup logs
  for "unknown entries" warnings

**Validation:** After configuring, check gateway stderr for warnings like:
```
agents.<id>.tools.allow allowlist contains unknown entries (<name>)
```
These warnings mean the tool name is not recognized and will be silently ignored.
```

---

### 6. `openclaw/SKILL.md` — Add `nomad alloc exec` as testing method

The skill's "Containerized gateway (homelab)" section only shows `podman exec`. For Nomad deployments, `nomad alloc exec` is the standard way to interact with containers.

**Update the containerized testing section:**

```markdown
### Containerized gateway (Nomad)

```bash
# Find the running allocation
nomad job status openclaw-gateway | grep running

# Exec into the container
nomad alloc exec <alloc-id> node openclaw.mjs agent \
  --agent <agent-id> --message "test message" --timeout 300

# Check gateway status
nomad alloc exec <alloc-id> node openclaw.mjs gateway status

# Check models
nomad alloc exec <alloc-id> node openclaw.mjs models list
```

**Note:** `nomad alloc exec` bypasses device pairing requirements. This is the
preferred way to test agents in a headless Nomad deployment where CLI pairing
is impractical.
```

---

### 7. `openclaw/SKILL.md` — Add config hot-reload behavior documentation

The skill mentions hot-reload exists but doesn't specify which config changes require a restart vs. hot-reload.

**Add a section:**

```markdown
### Config Reload Behavior

OpenClaw watches `openclaw.json` for changes and attempts hot-reload. Not all
changes can be applied without a restart.

**Hot-reloadable (no restart needed):**
- `agents.list` (add/remove/modify agents)
- `agents.defaults` (model routing, compaction, subagent limits)
- `models.providers` (add/remove providers, change URLs)
- `tools` (deny/allow changes)
- `bindings` (channel-agent bindings)

**Requires gateway restart:**
- `channels` (add/remove channel integrations)
- `plugins.entries` (enable/disable plugins)
- `gateway` (port, bind, auth changes)

The gateway logs reload decisions:
```
config change detected; evaluating reload (agents.list, models.providers)
config hot reload applied (agents.list)
```

Or when a restart is needed:
```
config change requires gateway restart (channels)
```

**Important:** Hot-reloaded model provider changes do NOT clear per-agent
`models.json` caches. Agents may continue using cached URLs until the cache
is manually deleted.
```

---

## Summary of Changes by File

| File | Changes |
|------|---------|
| `openclaw-provider-manager/SKILL.md` | Add per-agent model cache warning, LiteLLM dynamic port gotcha, memorySearch configuration section |
| `openclaw-agent-manager/SKILL.md` | Add Nomad/CephFS homelab deployment patterns section |
| `openclaw-agent-creator/SKILL.md` | Add valid tool names for allow lists, warn about glob/grep being invalid |
| `openclaw/SKILL.md` | Add `nomad alloc exec` testing method, add config hot-reload behavior docs |
