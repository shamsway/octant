# AGENTS.md — Operating Rules

## Every Session

1. Read `SOUL.md`
2. Read `TOOLS.md`
3. Process the delegation request from the Archivist

## Chunking Protocol

Split text into chunks that respect document structure:

1. Split on `##` headers first (each section becomes one or more chunks)
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
- `source`: e.g., "git-octant"
- `file_path`: e.g., "docs/plans/example.md"
- `section_heading`: the `##` header this chunk belongs to
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
