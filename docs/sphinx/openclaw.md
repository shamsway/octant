# OpenClaw & Knowledge Layer

## Overview

[OpenClaw](https://openclaw.dev) is an agent gateway that runs LLM-powered agents
as Nomad services. Agents communicate with users via Rocket.Chat and coordinate
with each other through delegated sessions. The gateway connects to local LLMs
served by vLLM on the hypervisor's MI300X GPU, proxied through LiteLLM.

The **knowledge layer** extends OpenClaw with a team of 4 agents that ingest
markdown and text into three backends — vector search (Qdrant), temporal knowledge
graph (Graphiti/Neo4j), and structured notes (Obsidian vault on CephFS). It
provides semantic retrieval, entity/relationship traversal, and full-text note
search across all indexed content.

```
User (Rocket.Chat)
  │
  ▼
OpenClaw Gateway (Nomad job, Podman)
  │
  ├── LiteLLM ──► vLLM (MI300X, 192.168.122.1)
  │
  ├── Agents
  │   ├── Archivist (knowledge hub)
  │   │   ├── Vec-Ingest  ──► Qdrant (vector search)
  │   │   ├── Graph-Ingest ──► Graphiti (knowledge graph)
  │   │   └── Notes-Ingest ──► Obsidian vault (CephFS)
  │   │
  │   └── [other teams: Scotty, ops, etc.]
  │
  └── Rocket.Chat (bot accounts)
```

## Gateway Architecture

### Deployment Model

The OpenClaw gateway runs as a Podman container on a Nomad rootless agent. Config
and workspace files live on CephFS, volume-mounted into the container.

```
Repo (source of truth)                    CephFS (runtime)
─────────────────────                    ────────────────
config/teams/<team>/                     /mnt/services/openclaw-gateway/
├── openclaw.json    ──── deploy ────►   ├── config/openclaw.json
└── workspaces/                          └── workspaces/<agent-id>/
    └── <agent-id>/  ──── scp ────────►      ├── SOUL.md
        ├── SOUL.md                          ├── AGENTS.md
        ├── AGENTS.md                        ├── TOOLS.md
        └── ...                              └── memory/
```

| Component | Location |
|-----------|----------|
| Terraform module | `terraform/openclaw-gateway/` |
| Team configs | `terraform/openclaw-gateway/config/teams/<team>/openclaw.json` |
| Workspace files | `terraform/openclaw-gateway/config/workspaces/<agent>/` |
| CephFS config | `/mnt/services/openclaw-gateway/config/openclaw.json` |
| CephFS workspaces | `/mnt/services/openclaw-gateway/workspaces/<agent>/` |
| Management CLI | `terraform/openclaw-gateway/botctl` |

### Model Routing

All LLM inference runs locally on the MI300X via vLLM, proxied through LiteLLM.

```
Agent ──► LiteLLM (litellm.lab.shamsway.net) ──► vLLM (192.168.122.1:8000)
```

- **Inference models:** Served by vLLM, accessed through LiteLLM's OpenAI-compatible
  API at `https://litellm.lab.shamsway.net/v1`
- **Embedding model:** `bge-large-en-v1.5` (1024 dimensions) for vector memory and
  Qdrant ingestion
- **LiteLLM dynamic ports:** Nomad assigns dynamic ports to LiteLLM. Always use the
  Traefik HTTPS URL (`https://litellm.lab.shamsway.net/v1`) in agent configs, not
  the Consul internal address

### Agent Workspace Structure

Every agent has a workspace directory with standard files:

| File | Purpose |
|------|---------|
| `SOUL.md` | Identity, values, boundaries (first person) |
| `IDENTITY.md` | Name, emoji, display info |
| `AGENTS.md` | Startup sequence, operating model, safety rules |
| `TOOLS.md` | API endpoints, tool inventory, lessons learned |
| `USER.md` | Operator context (shared across agents) |
| `HEARTBEAT.md` | Scheduled health checks and cron-driven tasks |
| `HANDOFFS.md` | Delegation contracts (hub agents only) |
| `memory/` | Persistent state (ingest tracking, learned facts) |

### Team Concept

Agents are organized into **teams** — named collections with a hub agent,
delegation patterns, and shared skills. The gateway loads one team config at a
time. Switching teams means deploying a different `openclaw.json`.

| Team | Agents | Hub | Purpose |
|------|--------|-----|---------|
| **scotty** | Scotty | Scotty | Single demo agent (MVP) |
| **knowledge** | Archivist, Vec-Ingest, Graph-Ingest, Notes-Ingest | Archivist | Knowledge ingestion and retrieval |
| **ops** | Navigator, Sentinel, Bosun | Navigator | Incident response (planned) |
| **combined** | All of the above | Navigator | Full stack (planned) |

### Config Management

| Change Type | Reload Method |
|-------------|--------------|
| Agent list, tool policy, model providers | Hot-reload (automatic) |
| Channel integrations, plugins | Requires allocation restart |
| Gateway settings (port, auth) | Requires allocation restart |

After provider URL changes, delete per-agent model caches to avoid stale routing:

```bash
rm /mnt/services/openclaw-gateway/config/agents/<id>/agent/models.json
```

## Knowledge Layer

### Agent Topology

The knowledge team has 4 agents with a hub-and-spoke delegation pattern:

```
              Archivist (hub)
              ┌──────────┐
              │ Routes    │
              │ store/    │
              │ retrieve  │
              └─────┬─────┘
      ┌─────────────┼─────────────┐
      ▼             ▼             ▼
┌───────────┐ ┌───────────┐ ┌───────────┐
│Vec-Ingest │ │Graph-Ingest│ │Notes-Ingest│
│           │ │           │ │           │
│ Chunks    │ │ Formats   │ │ Writes    │
│ text,     │ │ episodes  │ │ markdown  │
│ embeds,   │ │ for       │ │ notes to  │
│ upserts   │ │ Graphiti  │ │ Obsidian  │
│ to Qdrant │ │ API       │ │ vault     │
└───────────┘ └───────────┘ └───────────┘
```

| Agent | Role | Trigger | Model Size |
|-------|------|---------|------------|
| **Archivist** | Coordinator — routes store/retrieve requests, merges multi-backend results | User messages, cron (6h scan, 30m health) | Large (70B+) |
| **Vec-Ingest** | Chunks text, generates embeddings via LiteLLM, upserts to Qdrant | Delegated by Archivist | Small (8B) |
| **Graph-Ingest** | Formats episodes for Graphiti REST API (Graphiti handles entity extraction) | Delegated by Archivist | Small (8B) |
| **Notes-Ingest** | Writes structured markdown notes with frontmatter to Obsidian vault | Delegated by Archivist | Small (8B) |

### Knowledge Backends

| Backend | Endpoint | Purpose | Storage |
|---------|----------|---------|---------|
| Qdrant | `qdrant.service.consul:6333` | Semantic vector search | CSI RBD |
| Graphiti | `graphiti.service.consul:8000` | Temporal knowledge graph (entities, relationships) | Neo4j (CSI RBD) |
| Obsidian vault | `/mnt/services/obsidian/vault/` | Structured markdown notes | CephFS |
| LiteLLM | `litellm.lab.shamsway.net` | Embedding proxy (`bge-large-en-v1.5`) | — |

#### Qdrant Collections

| Collection | Content | Vector Dimension |
|------------|---------|-----------------|
| `docs` | Git repo docs, plans, READMEs | 1024 |
| `notes` | Obsidian vault notes | 1024 |
| `configs` | Terraform, Nomad HCL, Ansible | 1024 |

Each collection has payload indexes on `source` and `file_path` for filtered queries.

#### Obsidian Vault Layout

```
/mnt/services/obsidian/vault/
├── infrastructure/     # Octant docs, plans, runbooks
├── agents/             # Agent workspace summaries, lessons learned
├── incidents/          # Postmortems, incident notes
├── research/           # Web content, blog posts
└── daily/              # Daily notes, logs
```

Notes use YAML frontmatter (`title`, `source`, `created`, `updated`, `tags`)
and kebab-case filenames.

### Data Flows

#### Ingestion (Store)

When the Archivist receives content to store (ad-hoc or cron scan):

1. Compute SHA256 hash, check `memory/ingest-state.json` for changes
2. Fan out to backends via `sessions_spawn`:
   - **Vec-Ingest:** chunk text → embed via LiteLLM → upsert to Qdrant
   - **Graph-Ingest:** format as episode → POST to Graphiti (which does its own
     LLM-powered entity extraction)
   - **Notes-Ingest:** write markdown with frontmatter to vault (if explicitly
     requested)
3. Update `ingest-state.json` with new hashes and timestamps

```
Content ──► Archivist (hash check, dedup)
                │
     ┌──────────┼──────────┐
     ▼          ▼          ▼
  Vec-Ingest  Graph-Ingest Notes-Ingest
     │          │          │
     ▼          ▼          ▼
  Qdrant     Graphiti   Obsidian vault
```

#### Retrieval (Query)

When the Archivist receives a query:

1. Generate embedding for the query via LiteLLM
2. Query Qdrant for top-k semantic matches
3. Query Graphiti for entity/relationship traversal
4. Search Obsidian vault via file grep
5. Merge, deduplicate, and synthesize results with source attribution

```
Query ──► Archivist
              │
   ┌──────────┼──────────┐
   ▼          ▼          ▼
Qdrant     Graphiti   Obsidian
(semantic) (graph)    (grep)
   │          │          │
   └────┬─────┘──────────┘
        ▼
  Merged results with sources
```

#### Cron-Driven Scan

The Archivist runs on a 6-hour cron schedule to scan configured source paths for
new or modified files:

| Cron Job | Schedule | Action |
|----------|----------|--------|
| `ingestion-scan` | Every 6 hours | Scan paths, hash files, ingest changes |
| `backend-health` | Every 30 minutes | Verify Qdrant, Graphiti, vault accessible |

The ingestion scan only processes files whose SHA256 hash has changed since the
last run. Silent on routine scans — announces only when new content is indexed.

### Chunking Strategy

Vec-Ingest chunks text respecting document structure:

| Content Type | Chunk Size | Overlap | Split Strategy |
|---|---|---|---|
| Markdown docs | ~500 tokens | 50 tokens | `##` headers first, then paragraph boundaries |
| Code/configs | Per-block | None | Function/resource structural boundaries |
| Long-form text | ~800 tokens | 100 tokens | Paragraph boundaries |

Each chunk carries metadata: `source`, `file_path`, `section_heading`,
`chunk_index`, `timestamp`, `content_type`. Point IDs are deterministic
(SHA256 of `source:file_path:chunk_index`) for idempotent re-indexing.

### Inter-Agent Contracts

Delegation uses structured JSON request/response contracts:

| Delegation | Request | Response |
|------------|---------|----------|
| Archivist → Vec-Ingest | `{task, text, metadata, collection}` | `{status, points_upserted, collection}` |
| Archivist → Graph-Ingest | `{task, text, metadata, group_id}` | `{status, episode_id, entities_extracted, relationships_created}` |
| Archivist → Notes-Ingest | `{task, title, content, folder, tags}` | `{status, file_path, action}` |

### Tool Policies

Each agent has a strict tool policy matching its role:

| Agent | Policy | Rationale |
|-------|--------|-----------|
| Archivist | `allow: [exec, read, write, edit, group:web, group:sessions, ...]` | Orchestration, web for URL fetching |
| Vec-Ingest | `allow: [exec, memory_get, memory_search, message]` | Only curl to Qdrant/LiteLLM |
| Graph-Ingest | `allow: [exec, memory_get, memory_search, message]` | Only curl to Graphiti |
| Notes-Ingest | `allow: [exec, write, edit, read, message]` | File operations for CephFS writes |

## Deploying a New Agent Team

### Prerequisites

- LiteLLM running with the required models
- Embedding model available (if using vector memory or Qdrant)
- Rocket.Chat bot accounts created (see `docs/guides/openclaw-rocketchat-integration.md`)

### Workflow

1. **Design the team** — write `config/teams/<team>/team.md` with agent roster,
   contracts, and dependencies
2. **Author workspace files** — create `SOUL.md`, `AGENTS.md`, `TOOLS.md`, etc.
   for each agent
3. **Write team config** — create `config/teams/<team>/openclaw.json` with agent
   definitions, model providers, tool policies, and cron jobs
4. **Create CephFS volumes** — add entries to `inventory/groups.yml`, run the
   volumes playbook
5. **Update Nomad HCL** — add volume mounts for each agent workspace
6. **Deploy workspace files** — SCP from repo to CephFS
7. **Deploy team config** — copy `openclaw.json` to CephFS, restart gateway
8. **Validate** — check logs, run orientation prompts, verify backend connectivity

### Switching Teams

```bash
# Back up current config
ssh octant-01 'cp /mnt/services/openclaw-gateway/config/openclaw.json \
  /mnt/services/openclaw-gateway/config/openclaw.json.backup'

# Deploy new team config
scp config/teams/<team>/openclaw.json \
  octant-01:/mnt/services/openclaw-gateway/config/openclaw.json

# Restart gateway (required for channel/plugin changes)
./botctl gateway restart
```

### Validation

```bash
# Gateway health
nomad job status openclaw-gateway
./botctl gateway status

# Check for startup errors
./botctl gateway logs-err | tail -20

# Test each agent
./botctl agent orient <agent-id>
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Agent timeout | LiteLLM URL/port wrong | Use Traefik HTTPS URL in config |
| One agent fails, others work | Stale `models.json` cache | Delete `config/agents/<id>/agent/models.json` on CephFS |
| "allowlist contains unknown entries" | Invalid tool name | Remove from `allow` list; use valid names |
| Qdrant search returns nothing | Empty collection or wrong embedding model | Check `curl qdrant:6333/collections/<name>` for `points_count` |
| Graphiti 5xx errors | LLM timeout during entity extraction | Retry once; check Graphiti logs |
| Notes-Ingest can't write | CephFS permissions | Ensure vault dirs are `hashi:hashi` owned |
| Embedding dimension mismatch | Model changed without re-indexing | Recreate Qdrant collections, reset `ingest-state.json`, re-index |
| CephFS write not visible | Propagation delay | Wait 1-5 seconds; verify from the same node |

### Key Gotchas

- **Graphiti does its own entity extraction** — Graph-Ingest only formats and
  submits episodes, never pre-extracts entities
- **Embedding model changes invalidate all vector data** — changing the model
  requires recreating Qdrant collections and full re-indexing
- **`profile: "coding"` is expensive with local models** — the profile expands
  to a large tool schema. Use explicit `allow` lists instead
- **Per-agent model caches** — `agents/<id>/agent/models.json` caches provider
  URLs. Must be deleted after changing `baseUrl` or agents silently use the stale
  endpoint

## Reference

| Resource | Path |
|----------|------|
| Design doc | `docs/plans/2026-03-05-knowledge-layer-design.md` |
| Implementation plan | `docs/plans/2026-03-05-knowledge-layer-implementation.md` |
| Agent deployment guide | `docs/guides/openclaw-agent-deployment.md` |
| Rocket.Chat integration | `docs/guides/openclaw-rocketchat-integration.md` |
| Gateway design | `docs/plans/2026-03-02-openclaw-gateway-design.md` |
| botctl CLI | `terraform/openclaw-gateway/botctl` |
| Skill feedback | `docs/openclaw-skill-feedback.md` |
