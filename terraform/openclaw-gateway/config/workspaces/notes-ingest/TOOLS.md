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
