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

- Archivist -> Vec-Ingest: `{task, text, metadata, collection}` -> `{status, points_upserted, collection}`
- Archivist -> Graph-Ingest: `{task, text, metadata, group_id}` -> `{status, episode_id, entities_extracted, relationships_created}`
- Archivist -> Notes-Ingest: `{task, title, content, folder, tags, frontmatter}` -> `{status, file_path, action}`

## Dependencies

- Qdrant (`qdrant.service.consul:6333`)
- Graphiti (`graphiti.service.consul:8000`)
- LiteLLM (`litellm.service.consul:4000`) -- embedding endpoint
- CephFS (`/mnt/services/obsidian/vault/`)

## Combines With

- **ops**: Navigator becomes hub, Archivist becomes specialist. Add Archivist delegation stub to Navigator's HANDOFFS.md.
- **scotty**: Not designed for combination. Scotty is replaced by the knowledge team.
