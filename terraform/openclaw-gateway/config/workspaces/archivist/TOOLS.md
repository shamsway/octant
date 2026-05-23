# TOOLS.md — Knowledge Infrastructure

## Backends

| Backend | Endpoint | Purpose |
|---------|----------|---------|
| Qdrant | `http://qdrant.service.consul:6333` | Vector search (semantic similarity) |
| Graphiti | `https://graphiti.lab.shamsway.net` | Knowledge graph (entities, relationships, temporal) |
| Obsidian | `/mnt/services/obsidian/vault/` | Structured markdown notes (CephFS) |
| LiteLLM | `https://litellm.lab.shamsway.net` | Embedding model proxy |

## Qdrant API

Collections: `docs`, `notes`, `configs`

```
# Search
POST http://qdrant.service.consul:6333/collections/{collection}/points/search
{
  "vector": [<1024 floats>],
  "limit": 5,
  "with_payload": true,
  "filter": {"must": [{"key": "source", "match": {"value": "git-octant"}}]}
}

# Collection info (point count)
GET http://qdrant.service.consul:6333/collections/{collection}
```

## Graphiti API

```
# Search
POST https://graphiti.lab.shamsway.net/v1/search
{
  "query": "<natural language>",
  "group_ids": ["git-octant"],
  "num_results": 10
}

# Health
GET https://graphiti.lab.shamsway.net/healthcheck
```

## LiteLLM Embedding

```
POST https://litellm.lab.shamsway.net/v1/embeddings
Authorization: Bearer 8dNc3aNAEdrXnrLaVUcwnYAVz9bzgmJ3
Content-Type: application/json

{
  "model": "local/bge-large-en-v1.5",
  "input": "<text to embed>",
  "encoding_format": "float"
}
```

## Obsidian Vault

Path: `/mnt/services/obsidian/vault/`

Folders: `infrastructure/`, `agents/`, `incidents/`, `research/`, `daily/`

Search: `grep -rl "<query>" /mnt/services/obsidian/vault/`

## Source Scan Paths

| Source ID | Path | Content Type |
|-----------|------|--------------|
| git-octant-docs | `/mnt/services/obsidian/vault/` (or mounted repo) | Markdown docs, plans |

## Lessons Learned

- Graphiti handles its own LLM calls for entity extraction — do not duplicate
- CephFS propagation takes 1-5 seconds after writes
- Qdrant and Graphiti containers are stateless — terraform destroy/apply is the fix
- Embedding model changes require full re-indexing of all Qdrant collections
