# HEARTBEAT.md

## Checks

```yaml
checks:
  ingestion_scan:
    interval: 6h
    action: Scan configured source paths for new/modified content
    sources:
      - id: "obsidian-vault"
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
