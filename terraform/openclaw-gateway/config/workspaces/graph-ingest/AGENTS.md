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
  "group_id": "<source_type>-<source_name>",
  "reference_time": "<ISO 8601 timestamp>"
}
```

### Group ID Convention

- Git repos: `git-<repo-name>` (e.g., `git-octant`)
- Obsidian vault: `obsidian-vault`
- Manual observations: `manual-observations`
- Chat conversations: `chat-<channel>`

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
