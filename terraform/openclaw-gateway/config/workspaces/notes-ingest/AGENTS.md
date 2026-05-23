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
