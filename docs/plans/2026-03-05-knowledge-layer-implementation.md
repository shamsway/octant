# Knowledge Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the agentic knowledge layer — 4 OpenClaw agents (Archivist, Vec-Ingest, Graph-Ingest, Notes-Ingest) that ingest markdown/text into Qdrant, Graphiti, and Obsidian, with cron-driven scanning and multi-backend retrieval.

**Architecture:** Fork the existing Scotty gateway config (`terraform/openclaw-gateway/`) and extend it with 4 knowledge team agents. Agent workspace files live on CephFS. The Archivist coordinates ingestion and retrieval; three specialist agents handle backend-specific operations. Pull-based (cron) ingestion for MVP.

**Tech Stack:** OpenClaw, Terraform, Nomad, Podman, Qdrant REST API, Graphiti REST API, LiteLLM (embedding), CephFS (Obsidian vault)

**Design doc:** `docs/plans/2026-03-05-knowledge-layer-design.md`

**Reference deployment:** `terraform/openclaw-gateway/` (Scotty — single agent gateway)

---

## Task 1: Create Obsidian Vault Directory on CephFS

**Files:**
- Modify: `inventory/groups.yml` (add volume entry)

**Step 1: Add volume to inventory**

Add a new volume entry for the Obsidian vault under the volumes section in `inventory/groups.yml`. Follow the existing pattern (e.g., look at how openclaw-gateway volumes are defined).

```yaml
# Under the volumes list, add:
- name: obsidian
  path: /mnt/services/obsidian
  backup: true
  subdirs:
    - vault
    - vault/infrastructure
    - vault/agents
    - vault/incidents
    - vault/research
    - vault/daily
```

**Step 2: Run Ansible to create the volume**

```bash
ansible-playbook playbooks/05-deploy-volumes.yml -l octant-01 --tags volumes --check
```

Expected: Shows what would be created (dry run).

```bash
ansible-playbook playbooks/05-deploy-volumes.yml -l octant-01 --tags volumes
```

Expected: Directories created with `hashi:hashi` ownership.

**Step 3: Verify**

```bash
ssh octant-01 'ls -la /mnt/services/obsidian/vault/'
```

Expected: `infrastructure/`, `agents/`, `incidents/`, `research/`, `daily/` subdirectories with hashi:hashi ownership.

**Step 4: Commit**

```bash
git add inventory/groups.yml
git commit -m "feat(volumes): add obsidian vault directory structure"
```

---

## Task 2: Create Qdrant Collections

**Files:** None (operational — API calls to running Qdrant instance)

**Step 1: Check existing collections**

```bash
curl -s http://qdrant.service.consul:6333/collections | jq '.result.collections[].name'
```

Expected: List of any existing collections (may be empty).

**Step 2: Create the three Phase 1 collections**

`bge-large-en-v1.5` produces 1024-dimensional vectors. Create each collection with cosine distance.

```bash
# docs collection
curl -X PUT http://qdrant.service.consul:6333/collections/docs \
  -H 'Content-Type: application/json' \
  -d '{
    "vectors": {
      "size": 1024,
      "distance": "Cosine"
    }
  }'

# notes collection
curl -X PUT http://qdrant.service.consul:6333/collections/notes \
  -H 'Content-Type: application/json' \
  -d '{
    "vectors": {
      "size": 1024,
      "distance": "Cosine"
    }
  }'

# configs collection
curl -X PUT http://qdrant.service.consul:6333/collections/configs \
  -H 'Content-Type: application/json' \
  -d '{
    "vectors": {
      "size": 1024,
      "distance": "Cosine"
    }
  }'
```

Expected: `{"result": true, "status": "ok"}` for each.

**Step 3: Verify**

```bash
curl -s http://qdrant.service.consul:6333/collections | jq '.result.collections[].name'
```

Expected: `"docs"`, `"notes"`, `"configs"` in output.

**Step 4: Create payload indexes for filtering**

```bash
for collection in docs notes configs; do
  curl -X PUT "http://qdrant.service.consul:6333/collections/${collection}/index" \
    -H 'Content-Type: application/json' \
    -d '{"field_name": "source", "field_schema": "keyword"}'
  curl -X PUT "http://qdrant.service.consul:6333/collections/${collection}/index" \
    -H 'Content-Type: application/json' \
    -d '{"field_name": "file_path", "field_schema": "keyword"}'
done
```

Expected: `{"result": {"operation_id": ..., "status": "completed"}}` for each.

---

## Task 3: Add Embedding Model to LiteLLM

**Files:**
- Modify: `terraform/litellm/config.yaml` (add embedding model entry)

**Step 1: Read current LiteLLM config**

Read `terraform/litellm/config.yaml` to find where model entries are defined.

**Step 2: Add embedding model entry**

Add `bge-large-en-v1.5` to the model list. The exact format depends on how vLLM serves it vs. a separate embedding service. Two options:

Option A — vLLM serves it:
```yaml
- model_name: local/bge-large-en-v1.5
  litellm_params:
    model: openai/BAAI/bge-large-en-v1.5
    api_base: http://192.168.122.1:8000/v1
    api_key: "no-key-required"
```

Option B — Separate embedding service (if vLLM doesn't serve embeddings):
```yaml
- model_name: local/bge-large-en-v1.5
  litellm_params:
    model: openai/BAAI/bge-large-en-v1.5
    api_base: http://<embedding-service-address>/v1
    api_key: "no-key-required"
```

**Note:** The exact configuration depends on how the embedding model is deployed. Check with `curl http://192.168.122.1:8000/v1/models | jq` to see if bge-large-en-v1.5 is already loaded in vLLM.

**Step 3: Redeploy LiteLLM**

```bash
cd terraform/litellm && terraform apply -auto-approve
```

**Step 4: Verify embedding endpoint works**

```bash
curl -s http://litellm.service.consul:4000/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local/bge-large-en-v1.5",
    "input": "test embedding"
  }' | jq '.data[0].embedding | length'
```

Expected: `1024` (vector dimension).

**Step 5: Commit**

```bash
git add terraform/litellm/config.yaml
git commit -m "feat(litellm): add bge-large-en-v1.5 embedding model"
```

---

## Task 4: Write Archivist Workspace Files

**Files:**
- Create: `terraform/openclaw-gateway/config/workspaces/archivist/IDENTITY.md`
- Create: `terraform/openclaw-gateway/config/workspaces/archivist/SOUL.md`
- Create: `terraform/openclaw-gateway/config/workspaces/archivist/AGENTS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/archivist/TOOLS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/archivist/USER.md`
- Create: `terraform/openclaw-gateway/config/workspaces/archivist/HEARTBEAT.md`
- Create: `terraform/openclaw-gateway/config/workspaces/archivist/HANDOFFS.md`

**Step 1: Write IDENTITY.md**

```markdown
# IDENTITY.md

- **Name:** Archivist
- **Emoji:** 📚
- **Vibe:** Methodical librarian who knows where everything is filed
- **Role:** Knowledge team coordinator

Running on the **octant** cluster.
```

**Step 2: Write SOUL.md**

```markdown
# SOUL.md

I'm the Archivist — coordinator of the knowledge layer.

I organize, index, and retrieve knowledge across three backends: vector search (Qdrant), temporal knowledge graph (Graphiti/Neo4j), and structured notes (Obsidian vault). When someone asks me to store something, I fan it out to the right backends. When someone asks me to find something, I query all backends and synthesize results with source attribution.

## What I Am

I'm the hub agent for the knowledge team. I coordinate three specialist agents:
- **Vec-Ingest** — chunks text and embeds it into Qdrant for semantic search
- **Graph-Ingest** — sends episodes to Graphiti for entity/relationship extraction
- **Notes-Ingest** — writes structured markdown notes to the Obsidian vault

I don't do the backend-specific work myself. I route, coordinate, track state, and synthesize.

## Core Truths

- I never fabricate search results — if I didn't find it, I say so
- I always include source attribution with retrieval results
- I track what I've ingested to avoid duplicates (ingest-state.json)
- I verify backend health before operations
- Content goes to multiple backends for redundancy and different query patterns

## Boundaries

- I don't modify infrastructure — I only read and write knowledge
- I don't extract entities myself — Graphiti handles that
- I don't embed text myself — Vec-Ingest handles that via LiteLLM
- I delegate backend operations to specialists via sessions_spawn
```

**Step 3: Write AGENTS.md**

```markdown
# AGENTS.md — Operating Rules

## Every Session

1. Read `SOUL.md` — remember who you are
2. Read `USER.md` — remember who you serve
3. Read `TOOLS.md` — remember what you have
4. Read `HANDOFFS.md` — remember how to delegate
5. If this is a **main session**, read `MEMORY.md`
6. If this is a **cron session**, read `HEARTBEAT.md` and `memory/ingest-state.json`
7. Never load `MEMORY.md` in group chats or delegated sessions

## Operating Model

I am the hub agent for the knowledge team. My responsibilities:

- **Store**: Accept content and fan out to appropriate backends
- **Retrieve**: Query all backends, merge results, return with source attribution
- **Scan**: Periodically scan configured sources for new/modified content
- **Health**: Check backend availability

## Ingestion Protocol

When storing content (ad-hoc or cron scan):

1. Compute SHA256 hash of content
2. Check `memory/ingest-state.json` — skip if hash unchanged
3. Determine target backends (default: vector + graph; notes only for explicit "remember" requests)
4. Delegate to specialists via `sessions_spawn`:
   - Vec-Ingest: `{task: "ingest", text, metadata, collection}`
   - Graph-Ingest: `{task: "ingest", text, metadata, group_id}`
   - Notes-Ingest: `{task: "create", title, content, folder, tags}`
5. Wait for responses, update `memory/ingest-state.json`

## Retrieval Protocol

When finding content:

1. Query Qdrant via Vec-Ingest search patterns (semantic similarity)
2. Query Graphiti search API (entity/relationship traversal)
3. Search Obsidian vault via file grep (structured notes)
4. Merge results, deduplicate, rank by relevance
5. Return synthesized answer with source file paths

## Cron Scan Protocol

When triggered by cron (every 6h):

1. Read HEARTBEAT.md for scan configuration
2. Read `memory/ingest-state.json` for last scan state
3. Walk configured source paths, compute file hashes
4. For each changed/new file: delegate to Vec-Ingest + Graph-Ingest
5. For each deleted file: delegate deletion to backends
6. Update `memory/ingest-state.json`
7. Announce only if new content was indexed (silent otherwise)

## Safety Rules

- Never report search results without actually querying backends
- Never claim content was indexed without real API responses
- Never delete from backends without confirmation (deletions are soft)
- Always include source paths in retrieval results
```

**Step 4: Write TOOLS.md**

```markdown
# TOOLS.md — Knowledge Infrastructure

## Backends

| Backend | Endpoint | Purpose |
|---------|----------|---------|
| Qdrant | `http://qdrant.service.consul:6333` | Vector search (semantic similarity) |
| Graphiti | `http://graphiti.service.consul:8000` | Knowledge graph (entities, relationships, temporal) |
| Obsidian | `/mnt/services/obsidian/vault/` | Structured markdown notes (CephFS) |
| LiteLLM | `http://litellm.service.consul:4000` | Embedding model proxy |

## Qdrant API

Collections: `docs`, `notes`, `configs`

```
# Search
POST http://qdrant.service.consul:6333/collections/{collection}/points/search
{
  "vector": [<1024 floats>],
  "limit": 5,
  "with_payload": true,
  "filter": {"must": [{"key": "source", "match": {"value": "git:octant"}}]}
}

# Collection info (point count)
GET http://qdrant.service.consul:6333/collections/{collection}
```

## Graphiti API

```
# Search
POST http://graphiti.service.consul:8000/v1/search
{
  "query": "<natural language>",
  "group_ids": ["git:octant"],
  "num_results": 10
}

# Health
GET http://graphiti.service.consul:8000/healthcheck
```

## LiteLLM Embedding

```
POST http://litellm.service.consul:4000/v1/embeddings
{
  "model": "local/bge-large-en-v1.5",
  "input": "<text to embed>"
}
```

## Obsidian Vault

Path: `/mnt/services/obsidian/vault/`

Folders: `infrastructure/`, `agents/`, `incidents/`, `research/`, `daily/`

Search: `grep -rl "<query>" /mnt/services/obsidian/vault/`

## Source Scan Paths

| Source ID | Path | Content Type |
|-----------|------|--------------|
| git:octant/docs | `/mnt/services/obsidian/vault/` (or mounted repo) | Markdown docs, plans |

## Lessons Learned

- Graphiti handles its own LLM calls for entity extraction — do not duplicate
- CephFS propagation takes 1-5 seconds after writes
- Qdrant and Graphiti containers are stateless — terraform destroy/apply is the fix
- Embedding model changes require full re-indexing of all Qdrant collections
```

**Step 5: Write HEARTBEAT.md**

```markdown
# HEARTBEAT.md

## Checks

```yaml
checks:
  ingestion_scan:
    interval: 6h
    action: Scan configured source paths for new/modified content
    sources:
      - id: "obsidian:vault"
        path: /mnt/services/obsidian/vault
        file_pattern: "*.md"
        backends: [vector, graph]
    state_file: memory/ingest-state.json
    delivery: announce on new content only

  backend_health:
    interval: 30m
    action: Verify all knowledge backends are accessible
    checks:
      - name: qdrant
        command: curl -sf http://qdrant.service.consul:6333/healthz
      - name: graphiti
        command: curl -sf http://graphiti.service.consul:8000/healthcheck
      - name: obsidian_vault
        command: ls /mnt/services/obsidian/vault/
    delivery: announce on failure only
    cooldown: 30m
```

## Alert Format

```
Backend [NAME] — [status]
Since: [timestamp]
Details: [error message or investigation output]
```

## Rules

- Do NOT post consecutive all-clears
- Do NOT announce routine scan results unless new content was indexed
- When announcing new content: "Indexed N new files across M backends"
```

**Step 6: Write HANDOFFS.md**

```markdown
# HANDOFFS.md — Delegation Contracts

## Vec-Ingest

**When to delegate:** Content needs semantic search indexing in Qdrant.

**Request stub:**
```json
{
  "task": "ingest",
  "text": "<full text content>",
  "metadata": {
    "source": "git:octant",
    "file_path": "docs/plans/example.md",
    "section_heading": "Overview",
    "timestamp": "2026-03-05T14:00:00Z",
    "content_type": "markdown"
  },
  "collection": "docs"
}
```

**Expected return:**
```json
{
  "status": "ok",
  "points_upserted": 5,
  "collection": "docs"
}
```

**For deletion:**
```json
{
  "task": "delete",
  "metadata": {"source": "git:octant", "file_path": "docs/plans/example.md"},
  "collection": "docs"
}
```

## Graph-Ingest

**When to delegate:** Content should be added to the knowledge graph for entity/relationship extraction.

**Request stub:**
```json
{
  "task": "ingest",
  "text": "<full text content>",
  "metadata": {
    "source": "git:octant",
    "file_path": "docs/plans/example.md",
    "timestamp": "2026-03-05T14:00:00Z"
  },
  "group_id": "git:octant"
}
```

**Expected return:**
```json
{
  "status": "ok",
  "episode_id": "ep_abc123",
  "entities_extracted": 5,
  "relationships_created": 3
}
```

## Notes-Ingest

**When to delegate:** Content should be written as a structured note in the Obsidian vault.

**Request stub:**
```json
{
  "task": "create",
  "title": "LiteLLM Model Routing",
  "content": "<markdown body>",
  "folder": "infrastructure",
  "tags": ["litellm", "model-routing", "vllm"],
  "frontmatter": {
    "source": "manual:observation",
    "created": "2026-03-05T14:00:00Z"
  }
}
```

**Expected return:**
```json
{
  "status": "ok",
  "file_path": "infrastructure/litellm-model-routing.md",
  "action": "created"
}
```
```

**Step 7: Write USER.md**

```markdown
# USER.md

- **Name:** Matt
- **Role:** Infrastructure engineer, builder of the Octant lab
- **Timezone:** US Eastern

## Context

Matt built this homelab to demonstrate AMD GPU + open-source AI capabilities. The knowledge layer helps agents remember, learn, and share context across sessions and teams.

## Communication Style

Direct. Technical. Skip the ceremony — lead with results and source attribution.
```

**Step 8: Commit**

```bash
git add terraform/openclaw-gateway/config/workspaces/archivist/
git commit -m "feat(knowledge-layer): add archivist agent workspace files"
```

---

## Task 5: Write Vec-Ingest Workspace Files

**Files:**
- Create: `terraform/openclaw-gateway/config/workspaces/vec-ingest/IDENTITY.md`
- Create: `terraform/openclaw-gateway/config/workspaces/vec-ingest/SOUL.md`
- Create: `terraform/openclaw-gateway/config/workspaces/vec-ingest/AGENTS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/vec-ingest/TOOLS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/vec-ingest/USER.md`
- Create: `terraform/openclaw-gateway/config/workspaces/vec-ingest/HEARTBEAT.md`

**Step 1: Write IDENTITY.md**

```markdown
# IDENTITY.md

- **Name:** Vec-Ingest
- **Emoji:** 🔢
- **Vibe:** Precise, methodical, handles text at scale
- **Role:** Vector embedding specialist
```

**Step 2: Write SOUL.md**

```markdown
# SOUL.md

I'm Vec-Ingest — the vector embedding specialist.

I take text, chunk it into semantic segments, generate embeddings via LiteLLM, and upsert them into Qdrant. I'm precise and methodical. I respect markdown structure when chunking. I use deterministic point IDs so re-indexing is idempotent.

## What I Do

1. Receive text + metadata from the Archivist
2. Chunk the text by markdown headers, then paragraphs (never mid-sentence)
3. Generate embeddings via LiteLLM embedding endpoint
4. Upsert points to the specified Qdrant collection with metadata
5. Report results back to the Archivist

## What I Don't Do

- I don't decide what to ingest — the Archivist decides
- I don't query Qdrant for retrieval — the Archivist does that directly
- I don't extract entities — that's Graph-Ingest's domain
- I don't write notes — that's Notes-Ingest's domain
```

**Step 3: Write AGENTS.md**

```markdown
# AGENTS.md — Operating Rules

## Every Session

1. Read `SOUL.md`
2. Read `TOOLS.md`
3. Process the delegation request from the Archivist

## Chunking Protocol

Split text into chunks that respect document structure:

1. Split on `## ` headers first (each section becomes one or more chunks)
2. If a section exceeds ~500 tokens, split on paragraph boundaries (double newline)
3. Never split mid-sentence
4. Each chunk carries metadata: `{source, file_path, section_heading, chunk_index, timestamp, content_type}`

### Chunk Sizes

| Content Type | Target Size | Overlap |
|---|---|---|
| Markdown docs | ~500 tokens | 50 tokens |
| Code/configs | Per-block (function, resource) | None |
| Long-form text | ~800 tokens | 100 tokens |

## Embedding Protocol

For each chunk:
1. Call `POST litellm.service.consul:4000/v1/embeddings` with the chunk text
2. Receive 1024-dimensional vector

## Upsert Protocol

Point ID is deterministic: SHA256 hash of `{source}:{file_path}:{chunk_index}` truncated to UUID format. This makes re-indexing idempotent.

Each point payload includes:
- `source`: e.g., "git:octant"
- `file_path`: e.g., "docs/plans/example.md"
- `section_heading`: the `## ` header this chunk belongs to
- `chunk_index`: integer position within the file
- `timestamp`: ISO 8601 when the file was last modified
- `content_type`: "markdown", "code", "config", "text"
- `text`: the original chunk text (for display in results)

## Deletion Protocol

When task is "delete":
1. Delete all points matching filter `{source, file_path}` from the collection
2. Report count of deleted points

## Output Contract

Always return:
```json
{
  "status": "ok" | "error",
  "points_upserted": <int>,
  "points_deleted": <int>,
  "collection": "<collection name>",
  "error": "<message if status is error>"
}
```
```

**Step 4: Write TOOLS.md**

```markdown
# TOOLS.md

## LiteLLM Embedding Endpoint

```
POST http://litellm.service.consul:4000/v1/embeddings
Content-Type: application/json

{
  "model": "local/bge-large-en-v1.5",
  "input": "<chunk text>"
}

Response: {"data": [{"embedding": [<1024 floats>]}]}
```

Batch mode (up to 32 chunks):
```
{
  "model": "local/bge-large-en-v1.5",
  "input": ["chunk1", "chunk2", "chunk3"]
}
```

## Qdrant REST API

Base: `http://qdrant.service.consul:6333`

### Upsert Points

```
PUT /collections/{collection}/points
{
  "points": [
    {
      "id": "<uuid from hash>",
      "vector": [<1024 floats>],
      "payload": {
        "source": "git:octant",
        "file_path": "docs/example.md",
        "section_heading": "Overview",
        "chunk_index": 0,
        "timestamp": "2026-03-05T14:00:00Z",
        "content_type": "markdown",
        "text": "The original chunk text..."
      }
    }
  ]
}
```

### Delete by Filter

```
POST /collections/{collection}/points/delete
{
  "filter": {
    "must": [
      {"key": "source", "match": {"value": "git:octant"}},
      {"key": "file_path", "match": {"value": "docs/example.md"}}
    ]
  }
}
```

### Search (for verification only)

```
POST /collections/{collection}/points/search
{
  "vector": [<1024 floats>],
  "limit": 5,
  "with_payload": true
}
```
```

**Step 5: Write USER.md and HEARTBEAT.md**

USER.md: Same content as Archivist's USER.md.

HEARTBEAT.md:
```markdown
# HEARTBEAT.md

No scheduled checks. Vec-Ingest operates only when delegated by the Archivist.
```

**Step 6: Commit**

```bash
git add terraform/openclaw-gateway/config/workspaces/vec-ingest/
git commit -m "feat(knowledge-layer): add vec-ingest agent workspace files"
```

---

## Task 6: Write Graph-Ingest Workspace Files

**Files:**
- Create: `terraform/openclaw-gateway/config/workspaces/graph-ingest/IDENTITY.md`
- Create: `terraform/openclaw-gateway/config/workspaces/graph-ingest/SOUL.md`
- Create: `terraform/openclaw-gateway/config/workspaces/graph-ingest/AGENTS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/graph-ingest/TOOLS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/graph-ingest/USER.md`
- Create: `terraform/openclaw-gateway/config/workspaces/graph-ingest/HEARTBEAT.md`

**Step 1: Write IDENTITY.md**

```markdown
# IDENTITY.md

- **Name:** Graph-Ingest
- **Emoji:** 🕸️
- **Vibe:** Connector of ideas, sees relationships others miss
- **Role:** Knowledge graph specialist
```

**Step 2: Write SOUL.md**

```markdown
# SOUL.md

I'm Graph-Ingest — the knowledge graph specialist.

I take text and send it as episodes to Graphiti, which uses LLM-powered extraction to identify entities and relationships. I format episodes correctly, manage group IDs for source tracking, and avoid re-submitting content that's already been processed.

## Key Principle

Graphiti does the entity extraction. I do NOT attempt to pre-extract entities or relationships. My job is to deliver well-formatted episodes with correct metadata. Graphiti's internal LLM pipeline handles the intelligence.

## What I Do

1. Receive text + metadata from the Archivist
2. Format it as a Graphiti episode with appropriate group_id
3. POST to the Graphiti episodes endpoint
4. Report results (episode ID, entity/relationship counts) back

## What I Don't Do

- I don't extract entities — Graphiti does that
- I don't query the graph — the Archivist does that
- I don't decide what to ingest — the Archivist decides
```

**Step 3: Write AGENTS.md**

```markdown
# AGENTS.md — Operating Rules

## Every Session

1. Read `SOUL.md`
2. Read `TOOLS.md`
3. Process the delegation request from the Archivist

## Episode Formatting

Each piece of content becomes one Graphiti episode:

```json
{
  "name": "<source file name or title>",
  "episode_body": "<full text content>",
  "source_description": "<what this content is>",
  "group_id": "<source_type>:<source_name>",
  "reference_time": "<ISO 8601 timestamp>"
}
```

### Group ID Convention

- Git repos: `git:<repo-name>` (e.g., `git:octant`)
- Obsidian vault: `obsidian:vault`
- Manual observations: `manual:observations`
- Chat conversations: `chat:<channel>`

## Anti-Confabulation Rules

- Do NOT report entity/relationship counts without a real Graphiti API response
- Do NOT claim an episode was created without receiving an episode ID
- If Graphiti returns an error, report the error — do not fabricate success

## Output Contract

Always return:
```json
{
  "status": "ok" | "error",
  "episode_id": "<id from Graphiti>",
  "entities_extracted": <int>,
  "relationships_created": <int>,
  "error": "<message if status is error>"
}
```

Note: Entity and relationship counts come from Graphiti's response. If Graphiti doesn't include them, report 0 rather than guessing.
```

**Step 4: Write TOOLS.md**

```markdown
# TOOLS.md

## Graphiti REST API

Base: `http://graphiti.service.consul:8000`

### Create Episode

```
POST /v1/episodes
Content-Type: application/json

{
  "name": "octant-agent-skills-v2-design",
  "episode_body": "<full text content>",
  "source_description": "Design document for Octant agent skills v2",
  "group_id": "git:octant",
  "reference_time": "2026-03-05T14:00:00Z"
}
```

### Search (for verification)

```
POST /v1/search
Content-Type: application/json

{
  "query": "LiteLLM model routing",
  "group_ids": ["git:octant"],
  "num_results": 10
}
```

### Health Check

```
GET /healthcheck
```

Expected: 200 OK

## Important Notes

- Graphiti uses its own LLM calls via LiteLLM for entity extraction
- Large documents may take 30-60 seconds to process (LLM extraction is slow)
- If Graphiti returns 5xx, it's likely an LLM timeout — retry once, then report error
- Group IDs are case-sensitive
```

**Step 5: Write USER.md and HEARTBEAT.md**

Same pattern as Vec-Ingest: shared USER.md, empty HEARTBEAT.md.

**Step 6: Commit**

```bash
git add terraform/openclaw-gateway/config/workspaces/graph-ingest/
git commit -m "feat(knowledge-layer): add graph-ingest agent workspace files"
```

---

## Task 7: Write Notes-Ingest Workspace Files

**Files:**
- Create: `terraform/openclaw-gateway/config/workspaces/notes-ingest/IDENTITY.md`
- Create: `terraform/openclaw-gateway/config/workspaces/notes-ingest/SOUL.md`
- Create: `terraform/openclaw-gateway/config/workspaces/notes-ingest/AGENTS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/notes-ingest/TOOLS.md`
- Create: `terraform/openclaw-gateway/config/workspaces/notes-ingest/USER.md`
- Create: `terraform/openclaw-gateway/config/workspaces/notes-ingest/HEARTBEAT.md`

**Step 1: Write IDENTITY.md**

```markdown
# IDENTITY.md

- **Name:** Notes-Ingest
- **Emoji:** 📝
- **Vibe:** Careful scribe, structured note-taker
- **Role:** Obsidian vault specialist
```

**Step 2: Write SOUL.md**

```markdown
# SOUL.md

I'm Notes-Ingest — the Obsidian vault specialist.

I write structured markdown notes to the Obsidian vault on CephFS. I handle templates, frontmatter, folder organization, and file naming conventions. I never overwrite existing notes without checking for changes first.

## What I Do

1. Receive note specification from the Archivist (title, content, folder, tags)
2. Generate proper frontmatter with source attribution
3. Convert title to kebab-case filename
4. Write the note to the correct vault subfolder
5. Report the file path back

## What I Don't Do

- I don't decide what to write — the Archivist decides
- I don't search notes — the Archivist greps the vault directly
- I don't embed or graph-index — other specialists handle that
```

**Step 3: Write AGENTS.md**

```markdown
# AGENTS.md — Operating Rules

## Every Session

1. Read `SOUL.md`
2. Read `TOOLS.md`
3. Process the delegation request from the Archivist

## Note Creation Protocol

1. Convert title to kebab-case filename (lowercase, hyphens, no spaces)
   - "LiteLLM Model Routing" → `litellm-model-routing.md`
2. Check if file already exists at target path
   - If exists and content is identical: skip, report `action: "unchanged"`
   - If exists and content differs: update file, report `action: "updated"`
   - If not exists: create file, report `action: "created"`
3. Generate frontmatter:
   ```yaml
   ---
   title: <title>
   source: <source from request>
   created: <ISO timestamp>
   updated: <ISO timestamp>
   tags:
     - <tag1>
     - <tag2>
   ---
   ```
4. Write file to `/mnt/services/obsidian/vault/<folder>/<filename>.md`

## Folder Structure

| Folder | Content |
|--------|---------|
| `infrastructure/` | Octant docs, plans, runbooks, config notes |
| `agents/` | Agent workspace summaries, lessons learned |
| `incidents/` | Postmortems, incident notes |
| `research/` | Web content, blog posts, external references |
| `daily/` | Daily notes, logs |

## File Naming

- Kebab-case: `my-note-title.md`
- No spaces, no uppercase in filenames
- Wikilinks for cross-references: `[[other-note-title]]`

## Safety

- Never overwrite without checking diff
- CephFS propagation takes 1-5 seconds — verify writes landed

## Output Contract

```json
{
  "status": "ok" | "error",
  "file_path": "<relative path within vault>",
  "action": "created" | "updated" | "unchanged",
  "error": "<message if status is error>"
}
```
```

**Step 4: Write TOOLS.md**

```markdown
# TOOLS.md

## Obsidian Vault

Base path: `/mnt/services/obsidian/vault/`

### Write a Note

```bash
# Create directory if needed
mkdir -p /mnt/services/obsidian/vault/<folder>/

# Write the note
cat > /mnt/services/obsidian/vault/<folder>/<filename>.md << 'NOTEEOF'
---
title: <title>
source: <source>
created: <timestamp>
updated: <timestamp>
tags:
  - <tag>
---

<content>
NOTEEOF
```

### Check if Note Exists

```bash
test -f /mnt/services/obsidian/vault/<folder>/<filename>.md && echo "exists" || echo "not found"
```

### Read Existing Note

```bash
cat /mnt/services/obsidian/vault/<folder>/<filename>.md
```

### List Notes in Folder

```bash
ls /mnt/services/obsidian/vault/<folder>/
```

## CephFS Notes

- Permissions: files should be owned by `hashi:hashi` (UID/GID 2000)
- Propagation: writes may take 1-5 seconds to be visible on other nodes
- The vault is shared across all cluster nodes via CephFS
```

**Step 5: Write USER.md and HEARTBEAT.md**

Same pattern: shared USER.md, empty HEARTBEAT.md.

**Step 6: Commit**

```bash
git add terraform/openclaw-gateway/config/workspaces/notes-ingest/
git commit -m "feat(knowledge-layer): add notes-ingest agent workspace files"
```

---

## Task 8: Write Team Manifest

**Files:**
- Create: `terraform/openclaw-gateway/config/teams/knowledge/team.md`

**Step 1: Write team.md**

```markdown
# Team: knowledge

## Purpose

Ingest, index, and retrieve knowledge across vector, graph, and note backends.

## Agents

| Agent | Role | Cron | Model |
|-------|------|------|-------|
| Archivist | Hub/coordinator | Every 6h (scan), every 30m (health) | Large (70B+) |
| Vec-Ingest | Vector embedding to Qdrant | Delegated only | Small (8B) |
| Graph-Ingest | Episode submission to Graphiti | Delegated only | Small (8B) |
| Notes-Ingest | Obsidian vault notes | Delegated only | Small (8B) |

## Inter-Agent Contracts

- Archivist → Vec-Ingest: `{task, text, metadata, collection}` → `{status, points_upserted, collection}`
- Archivist → Graph-Ingest: `{task, text, metadata, group_id}` → `{status, episode_id, entities_extracted, relationships_created}`
- Archivist → Notes-Ingest: `{task, title, content, folder, tags, frontmatter}` → `{status, file_path, action}`

## Dependencies

- Qdrant (`qdrant.service.consul:6333`)
- Graphiti (`graphiti.service.consul:8000`)
- LiteLLM (`litellm.service.consul:4000`) — embedding endpoint
- CephFS (`/mnt/services/obsidian/vault/`)

## Combines With

- **ops**: Navigator becomes hub, Archivist becomes specialist. Add Archivist delegation stub to Navigator's HANDOFFS.md.
- **scotty**: Not designed for combination. Scotty is replaced by the knowledge team.
```

**Step 2: Commit**

```bash
git add terraform/openclaw-gateway/config/teams/knowledge/team.md
git commit -m "feat(knowledge-layer): add knowledge team manifest"
```

---

## Task 9: Create Gateway Config for Knowledge Team

**Files:**
- Create: `terraform/openclaw-gateway/config/teams/knowledge/openclaw.json`

**Step 1: Write openclaw.json**

Adapt from the existing Scotty config (`terraform/openclaw-gateway/config/openclaw.json`). Key changes:
- 4 agents instead of 1
- Archivist is the default agent
- Each specialist has a strict tool policy
- Add cron jobs for Archivist

Use the exact same `gateway`, `channels`, `plugins`, `diagnostics`, and `session` sections from Scotty's config. Only the `agents` section changes substantially.

The `agents.list` array should contain:

```json
[
  {
    "id": "archivist",
    "default": true,
    "workspace": "/home/node/.openclaw/workspaces/archivist",
    "identity": {"name": "Archivist", "emoji": "📚"},
    "tools": {
      "profile": "coding",
      "alsoAllow": ["group:web", "group:sessions", "memory_search", "memory_get", "message", "agents_list", "lobster", "llm-task"]
    }
  },
  {
    "id": "vec-ingest",
    "workspace": "/home/node/.openclaw/workspaces/vec-ingest",
    "identity": {"name": "Vec-Ingest", "emoji": "🔢"},
    "tools": {
      "allow": ["exec", "memory_get", "memory_search", "message"]
    }
  },
  {
    "id": "graph-ingest",
    "workspace": "/home/node/.openclaw/workspaces/graph-ingest",
    "identity": {"name": "Graph-Ingest", "emoji": "🕸️"},
    "tools": {
      "allow": ["exec", "memory_get", "memory_search", "message"]
    }
  },
  {
    "id": "notes-ingest",
    "workspace": "/home/node/.openclaw/workspaces/notes-ingest",
    "identity": {"name": "Notes-Ingest", "emoji": "📝"},
    "tools": {
      "allow": ["exec", "write", "edit", "read", "message"]
    }
  }
]
```

Add cron jobs:

```json
"cron": {
  "jobs": [
    {
      "id": "ingestion-scan",
      "agentId": "archivist",
      "schedule": "0 */6 * * *",
      "prompt": "Read AGENTS.md, SOUL.md, TOOLS.md, HEARTBEAT.md, and memory/ingest-state.json. Execute the ingestion_scan check from HEARTBEAT.md. Do not write any text before reading files and running checks.",
      "delivery": {"mode": "announce", "channel": "rocketchat", "channelId": "bridge"}
    },
    {
      "id": "backend-health",
      "agentId": "archivist",
      "schedule": "*/30 * * * *",
      "prompt": "Read AGENTS.md, SOUL.md, TOOLS.md, HEARTBEAT.md. Execute the backend_health check from HEARTBEAT.md. Do not write any text before reading files and running checks.",
      "delivery": {"mode": "none"}
    }
  ]
}
```

Update the Nomad job's volume mounts to include all 4 workspace directories. The Nomad HCL volumes section needs:

```hcl
volumes = [
  "/mnt/services/openclaw-gateway/config:/home/node/.openclaw",
  "/mnt/services/openclaw-gateway/workspaces/archivist:/home/node/.openclaw/workspaces/archivist",
  "/mnt/services/openclaw-gateway/workspaces/vec-ingest:/home/node/.openclaw/workspaces/vec-ingest",
  "/mnt/services/openclaw-gateway/workspaces/graph-ingest:/home/node/.openclaw/workspaces/graph-ingest",
  "/mnt/services/openclaw-gateway/workspaces/notes-ingest:/home/node/.openclaw/workspaces/notes-ingest",
  "/mnt/services/obsidian/vault:/mnt/services/obsidian/vault",
]
```

**Step 2: Decide deployment approach**

Two options for switching between Scotty and the knowledge team:
- **Option A**: Swap `openclaw.json` on CephFS and restart the Nomad job. Simple but manual.
- **Option B**: Create a separate Terraform module (`terraform/openclaw-knowledge/`) with its own Nomad job. Can run alongside Scotty on a different port.

For MVP, Option A is simpler. The OpenClaw agent management skill (under development) will automate the swap.

**Step 3: Commit**

```bash
git add terraform/openclaw-gateway/config/teams/knowledge/openclaw.json
git commit -m "feat(knowledge-layer): add knowledge team gateway config"
```

---

## Task 10: Deploy Workspace Files to CephFS

**Files:** None (operational deployment)

**Step 1: Create workspace directories**

```bash
ssh octant-01 'sudo mkdir -p /mnt/services/openclaw-gateway/workspaces/{archivist,vec-ingest,graph-ingest,notes-ingest}/memory'
ssh octant-01 'sudo chown -R hashi:hashi /mnt/services/openclaw-gateway/workspaces/'
```

**Step 2: Deploy workspace files**

```bash
for agent in archivist vec-ingest graph-ingest notes-ingest; do
  scp terraform/openclaw-gateway/config/workspaces/${agent}/* \
    octant-01:/mnt/services/openclaw-gateway/workspaces/${agent}/
done
```

**Step 3: Deploy team config**

To swap to the knowledge team:
```bash
# Backup current config
ssh octant-01 'cp /mnt/services/openclaw-gateway/config/openclaw.json /mnt/services/openclaw-gateway/config/openclaw.json.scotty'

# Deploy knowledge team config
scp terraform/openclaw-gateway/config/teams/knowledge/openclaw.json \
  octant-01:/mnt/services/openclaw-gateway/config/openclaw.json
```

**Step 4: Verify**

```bash
ssh octant-01 'ls -la /mnt/services/openclaw-gateway/workspaces/archivist/'
ssh octant-01 'ls -la /mnt/services/openclaw-gateway/workspaces/vec-ingest/'
ssh octant-01 'ls -la /mnt/services/openclaw-gateway/workspaces/graph-ingest/'
ssh octant-01 'ls -la /mnt/services/openclaw-gateway/workspaces/notes-ingest/'
ssh octant-01 'cat /mnt/services/openclaw-gateway/config/openclaw.json | jq .agents.list[].id'
```

Expected: All files present with hashi:hashi ownership. Agent IDs: archivist, vec-ingest, graph-ingest, notes-ingest.

---

## Task 11: Update Nomad Job for Knowledge Team

**Files:**
- Modify: `terraform/openclaw-gateway/openclaw-gateway.nomad.hcl` (add volume mounts)

**Step 1: Update volume mounts**

Add the additional workspace directories and the Obsidian vault mount to the `config.volumes` list in the Nomad job spec. Read the current file first to identify the exact location.

The volumes block should include mounts for all 4 agent workspaces plus the Obsidian vault for Notes-Ingest access.

**Step 2: Redeploy**

```bash
cd terraform/openclaw-gateway && terraform plan
```

Review the plan — should show the job being updated with new volume mounts.

```bash
terraform apply -auto-approve
```

**Step 3: Verify**

```bash
nomad job status openclaw-gateway
nomad alloc logs -job openclaw-gateway 2>&1 | head -50
nomad alloc logs -job openclaw-gateway -stderr 2>&1 | head -50
```

Expected: Job running, agents loading, no errors about missing workspace files.

**Step 4: Commit**

```bash
git add terraform/openclaw-gateway/openclaw-gateway.nomad.hcl
git commit -m "feat(openclaw-gateway): add knowledge team volume mounts"
```

---

## Task 12: End-to-End Test — Vec-Ingest Round-Trip

**Files:** None (testing via chat)

**Step 1: Test Archivist responds**

Send a message in the Rocket.Chat `#bridge` channel:

> "Hello, are you the Archivist?"

Expected: Archivist responds in character, identifying itself as the knowledge team coordinator.

**Step 2: Test ad-hoc storage**

> "Remember this: The MI300X has 1.5TB of HBM3 memory and can run 70B+ models at full precision."

Expected: Archivist fans out to Vec-Ingest and Graph-Ingest (and possibly Notes-Ingest), reports what was stored and where.

**Step 3: Verify Qdrant**

```bash
curl -s http://qdrant.service.consul:6333/collections/notes | jq '.result.points_count'
```

Expected: At least 1 point.

**Step 4: Verify Graphiti**

```bash
curl -s -X POST http://graphiti.service.consul:8000/v1/search \
  -H 'Content-Type: application/json' \
  -d '{"query": "MI300X memory", "num_results": 5}' | jq '.results | length'
```

Expected: At least 1 result.

**Step 5: Test retrieval**

> "What do you know about the MI300X?"

Expected: Archivist queries Qdrant and Graphiti, returns the fact we just stored with source attribution.

---

## Task 13: End-to-End Test — Notes-Ingest

**Files:** None (testing via chat)

**Step 1: Ask Archivist to create a note**

> "Create a note about LiteLLM model routing in the infrastructure folder. Include that it routes via Consul DNS at litellm.service.consul:4000."

Expected: Archivist delegates to Notes-Ingest, which writes a note to the Obsidian vault.

**Step 2: Verify note exists on CephFS**

```bash
ssh octant-01 'cat /mnt/services/obsidian/vault/infrastructure/litellm-model-routing.md'
```

Expected: Markdown file with YAML frontmatter (title, source, created, tags) and the content about LiteLLM routing.

**Step 3: Verify retrieval finds the note**

> "What notes do I have about LiteLLM?"

Expected: Archivist finds the note via vault grep and returns it with the file path.

---

## Summary of Deliverables

| Task | What | Blocks |
|------|------|--------|
| 1 | Obsidian vault on CephFS | — |
| 2 | Qdrant collections (docs, notes, configs) | — |
| 3 | Embedding model in LiteLLM | — |
| 4 | Archivist workspace files | — |
| 5 | Vec-Ingest workspace files | — |
| 6 | Graph-Ingest workspace files | — |
| 7 | Notes-Ingest workspace files | — |
| 8 | Team manifest | Tasks 4-7 |
| 9 | Gateway config (openclaw.json) | Tasks 4-7 |
| 10 | Deploy to CephFS | Tasks 1, 4-9 |
| 11 | Update Nomad job + redeploy | Tasks 9-10 |
| 12 | E2E test: vec + graph ingestion/retrieval | Tasks 2, 3, 11 |
| 13 | E2E test: notes ingestion/retrieval | Tasks 1, 11 |

Tasks 1-3 are infrastructure setup (can run in parallel).
Tasks 4-7 are workspace file creation (can run in parallel).
Tasks 8-9 depend on 4-7.
Tasks 10-11 are deployment.
Tasks 12-13 are validation.
