# TOOLS.md

## Graphiti REST API

Base: `https://graphiti.lab.shamsway.net`

### Create Episode

```
POST /v1/episodes
Content-Type: application/json

{
  "name": "octant-agent-skills-v2-design",
  "episode_body": "<full text content>",
  "source_description": "Design document for Octant agent skills v2",
  "group_id": "git-octant",
  "reference_time": "2026-03-05T14:00:00Z"
}
```

### Search (for verification)

```
POST /v1/search
Content-Type: application/json

{
  "query": "LiteLLM model routing",
  "group_ids": ["git-octant"],
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
