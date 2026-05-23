# Knowledge Layer E2E Testing Notes — 2026-03-13

## Summary

Full end-to-end testing of the knowledge layer (Archivist, Vec-Ingest, Graph-Ingest, Notes-Ingest agents) with Qdrant, Graphiti/Neo4j, and Obsidian vault backends. All three backends verified working with local models only (no OpenAI billing).

## Test Results

| Backend | Status | Evidence |
|---------|--------|----------|
| Qdrant | Working | 1 point upserted to `notes` collection, semantic search returns 0.68 similarity match |
| Graphiti/Neo4j | Working | 1 episode ingested, 5 entities extracted, 4 relationships created. Search returns structured facts. |
| Obsidian | Working | Note written to `vault/agents/preferences/matt.md` |

### Graphiti Search Output

```json
{
  "facts": [
    {"name": "DISLIKES", "fact": "Matt dislikes peas"},
    {"name": "FAVORITE_DESSERT", "fact": "his favorite dessert is cheesecake"},
    {"name": "RUNS", "fact": "He runs a homelab called Octant"},
    {"name": "HAS_NODES", "fact": "Octant with 3 AMD GPU nodes"}
  ]
}
```

## Issues Found & Fixed

### 1. Dynamic Nomad Ports (Graphiti + LiteLLM)

**Problem:** Agent TOOLS.md files hardcoded `http://graphiti.service.consul:8000` and `http://litellm.service.consul:4000`. Both services use dynamic Nomad ports — Consul DNS resolves the hostname but not the port.

**Fix (agents):** Switched to Traefik URLs in all agent TOOLS.md files:
- Graphiti: `https://graphiti.lab.shamsway.net`
- LiteLLM: `https://litellm.lab.shamsway.net`

**Fix (Graphiti Nomad job):** Moved `OPENAI_BASE_URL` from hardcoded env var into Consul template block (same pattern already used for Neo4j):
```hcl
{{ range service "litellm" -}}
OPENAI_BASE_URL=http://{{ .Address }}:{{ .Port }}/v1
{{- end }}
```

### 2. LiteLLM Auth Required via Traefik

**Problem:** LiteLLM enforces `LITELLM_MASTER_KEY` auth. Agents calling via Traefik URL need the bearer token.

**Fix:** Added `Authorization: Bearer <key>` to TOOLS.md curl examples. Key is already in the gateway config on the same CephFS mount (same security boundary).

### 3. MiniMax-M2.5 `<think>` Tags Break Structured Output

**Problem:** Graphiti expects clean JSON from `response_format: json_object`. vLLM with `--reasoning-parser minimax_m2_append_think` bakes `<think>` reasoning into the response `content` field, breaking JSON parsing.

**Fix:** Switch vLLM to `--reasoning-parser minimax_m2`. This separates thinking into a `reasoning_content` field, keeping `content` clean for structured output consumers.

### 4. Missing LiteLLM Model Aliases

**Problem:** Graphiti defaults to `gpt-4.1-mini` (main LLM), `gpt-4.1-nano` (small model), and `text-embedding-3-small` (embedder). None existed in LiteLLM.

**Fix:** Added aliases in `terraform/litellm/config.yaml` routing all to local vLLM models:

| Alias | Routes to | vLLM Instance |
|-------|-----------|---------------|
| `gpt-4.1-mini` | `openai/minimax-m2.5` | `:8000` |
| `gpt-4.1-nano` | `openai/minimax-m2.5` | `:8000` |
| `text-embedding-3-small` | `openai/bge-large-en-v1.5` | `:8001` |

### 5. Graphiti `group_id` Validation — No Colons

**Problem:** Graphiti requires group IDs to contain only alphanumeric characters, dashes, or underscores. Our convention used colons (`git:octant`). The `/messages` endpoint returns 202 (accepted) but the async background worker throws `GroupIdValidationError` silently — no error in stdout, nothing in Neo4j.

**Fix:** Changed all group_id and source conventions from colons to dashes:
- `git:octant` → `git-octant`
- `obsidian:vault` → `obsidian-vault`
- `manual:observation` → `manual-observation`
- `chat:<channel>` → `chat-<channel>`

Updated across all 4 agent workspace directories (TOOLS.md, AGENTS.md, HANDOFFS.md, HEARTBEAT.md).

### 6. LiteLLM `encoding_format: null` Error

**Problem:** vLLM rejects `encoding_format: null` in embedding requests. LiteLLM's `drop_params: True` doesn't catch this — it passes `null` instead of omitting the field.

**Fix:** Always include `"encoding_format": "float"` in embedding requests in TOOLS.md examples.

### 7. Missing Qdrant Collections

**Problem:** `docs` and `configs` collections were lost to a Qdrant redeploy. Only `notes` remained.

**Fix:** Recreated all three collections (1024-dim cosine) with `source` and `file_path` keyword payload indexes. Note: Qdrant collections don't survive `terraform destroy/apply` — need to recreate after redeploys.

### 8. LiteLLM `force_pull` + Disk Space

**Problem:** LiteLLM Nomad job has `force_pull = "true"`, re-downloading the 1.85GB image on every restart. Failed with "no space left on device" on octant-02 due to stale Podman images.

**Fix:** `podman system prune -f` on the target node freed 1.9GB. Long-term: consider removing `force_pull` or pinning to a specific tag.

## Service Endpoints (Current)

| Service | Agent URL (via Traefik) | Internal URL | Port Type |
|---------|------------------------|--------------|-----------|
| Qdrant | N/A (static port) | `http://qdrant.service.consul:6333` | Static |
| Graphiti | `https://graphiti.lab.shamsway.net` | Dynamic (Consul catalog) | Dynamic |
| LiteLLM | `https://litellm.lab.shamsway.net` | Dynamic (Consul catalog) | Dynamic |
| Neo4j | `https://neo4j.lab.shamsway.net` | Dynamic (Consul catalog) | Dynamic |
| Obsidian vault | N/A (filesystem) | `/mnt/services/obsidian/vault/` | CephFS |

## Performance Notes

- Graphiti entity extraction with local minimax-m2.5 (70B): ~6-10 LLM calls per episode, ~2-5 minutes total
- Embedding via bge-large-en-v1.5: sub-second for single inputs
- Qdrant upsert/search: sub-second

## Files Changed

```
terraform/graphiti/graphiti.nomad.hcl          # Consul template for OPENAI_BASE_URL
terraform/litellm/config.yaml                  # Model aliases for Graphiti
terraform/openclaw-gateway/config/workspaces/
  archivist/{TOOLS,HANDOFFS,HEARTBEAT}.md      # Traefik URLs, dash group IDs
  vec-ingest/{TOOLS,AGENTS}.md                 # Traefik URLs, dash group IDs
  graph-ingest/{TOOLS,AGENTS}.md               # Traefik URLs, dash group IDs
```

Commit: `70510c1 fix(knowledge-layer): fix backend connectivity and Graphiti integration`
