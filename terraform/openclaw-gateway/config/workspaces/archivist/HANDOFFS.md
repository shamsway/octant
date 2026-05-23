# HANDOFFS.md — Delegation Contracts

## Vec-Ingest

**When to delegate:** Content needs semantic search indexing in Qdrant.

**Request stub:**
```json
{
  "task": "ingest",
  "text": "<full text content>",
  "metadata": {
    "source": "git-octant",
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
  "metadata": {"source": "git-octant", "file_path": "docs/plans/example.md"},
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
    "source": "git-octant",
    "file_path": "docs/plans/example.md",
    "timestamp": "2026-03-05T14:00:00Z"
  },
  "group_id": "git-octant"
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
    "source": "manual-observation",
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
