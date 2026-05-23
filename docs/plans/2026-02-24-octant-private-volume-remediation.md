# Octant-Private Volume Remediation Plan

**Repo:** `octant-private`
**Priority:** Medium — these are pre-existing bugs, not regressions

---

## Issue 1: Weaviate path typo (`weviate` → `weaviate`)

**Severity:** High — volume mount path doesn't match inventory path

**Problem:** The inventory defines volumes with correct spelling (`weaviate-config`, `weaviate-data`) but the directory paths use the misspelling `weviate`:

- `inventory/groups.yml` — paths are `/mnt/services/weaviate/data` (correct spelling)
- `terraform/weaviate/weviate.nomad.hcl:67` — volume mount uses `/mnt/services/weviate/data` (wrong)

The terraform job creates containers looking for `/mnt/services/weviate/data` but the volumes role creates `/mnt/services/weaviate/data`. The data directory is never actually populated.

**Fix:**
1. In `terraform/weaviate/weviate.nomad.hcl` line 67, change `/mnt/services/weviate/data` → `/mnt/services/weaviate/data`
2. Rename `terraform/weaviate/weviate.nomad.hcl` → `terraform/weaviate/weaviate.nomad.hcl`
3. Update any `main.tf` referencing the old filename
4. On live cluster: `mv /mnt/services/weviate /mnt/services/weaviate` (if data exists)

---

## Issue 2: pgadmin volume mount commented out

**Severity:** Medium — pgadmin data is ephemeral (lost on container restart)

**Problem:** `terraform/pgadmin/pgadmin.nomad.hcl` line 58 has the volume mount commented out:

```hcl
#volumes = ["/mnt/services/pgadmin/data:/var/lib/pgadmin"]
```

The `pgadmin-data` volume is correctly defined in `inventory/groups.yml` line 199-201 and the volumes role creates the directory, but the Nomad job never mounts it. Any pgAdmin saved connections, query history, etc. are lost on restart.

**Fix:**
1. Uncomment the volumes line in `terraform/pgadmin/pgadmin.nomad.hcl`
2. Verify pgadmin container user (typically UID 5050) can write to the mounted path — may need `mode: "0777"` or `owner`/`group` override in inventory, or `userns` mapping in the podman config

---

## Issue 3: musicassistant volume mismatch

**Severity:** Low — works in practice but volume definitions are misleading

**Problem:** The Nomad job mounts the parent directory, but inventory only defines subdirectories:

- `terraform/homeassitant/homeassistant.nomad.hcl:183` mounts `/mnt/services/musicassistant:/data`
- Inventory defines `musicassistant-cache` → `/mnt/services/musicassistant/.cache` and `musicassistant-playlists` → `/mnt/services/musicassistant/playlists`

This works because the volumes role creates the subdirectories, which implicitly creates the parent. But the parent `/mnt/services/musicassistant` itself is never declared as a volume, so it won't appear in Nomad host volume lists or backup configurations.

**Fix (pick one):**
- **Option A:** Add a parent volume entry `musicassistant` → `/mnt/services/musicassistant` and set `manage_permissions: false` on the subdirectory entries (container manages those)
- **Option B:** Change the Nomad job to mount the specific subdirectories instead of the parent

**Also note:** The terraform directory is misspelled as `homeassitant` (missing an 's'). Consider renaming to `homeassistant` at the same time.
