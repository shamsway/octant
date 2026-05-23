# TOOLS.md

## LiteLLM Embedding Endpoint

```
POST https://litellm.lab.shamsway.net/v1/embeddings
Authorization: Bearer 8dNc3aNAEdrXnrLaVUcwnYAVz9bzgmJ3
Content-Type: application/json

{
  "model": "local/bge-large-en-v1.5",
  "input": "<chunk text>",
  "encoding_format": "float"
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
        "source": "git-octant",
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
      {"key": "source", "match": {"value": "git-octant"}},
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
