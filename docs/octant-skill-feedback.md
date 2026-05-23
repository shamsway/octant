# Octant Skill Feedback: Knowledge Layer Deployment Session

**Date**: 2026-03-03
**Services deployed**: NATS, FalkorDB, Neo4j, Graphiti
**Skills used**: `octant-autodeploy`, `octant-volumes`, `octant-validation`, `octant-autodeploy/patterns/user-namespace.md`

---

## Deployment Session Retrospective

### Issues Encountered (in order)

| # | Issue | Root Cause | Severity |
|---|-------|-----------|----------|
| 1 | `make deploy-role ROLE=volumes` didn't create dirs | `volumes` role not in `octant.yml`; need `playbooks/05-deploy-volumes.yml` | Low |
| 2 | NATS alloc failed — volume path missing | CephFS propagation delay; first allocs hit before dirs existed on all nodes | Low (self-healed) |
| 3 | `nomad fmt` errors on templatefile HCL | Expected — `${dns}` is Terraform interpolation, not valid standalone HCL | None (known) |
| 4 | Graphiti `/root/.local/bin/uv: Permission denied` | Image installs `uv` as root in `/root/` then sets `USER app`. Rootless Podman enforces this. | High |
| 5 | Tried `userns = "keep-id"` with `user = "2000:2000"` | Didn't help — `app` user still can't access `/root/` directory | Medium |
| 6 | Tried `userns = "keep-id:uid=0,gid=0"` | OCI runtime error — `gid_map` write failed, unsupported by crun version | Medium |
| 7 | Fix: `user = "root"` (no userns) on rootless agent | Works — rootless Podman maps container root to hashi user on host | n/a |
| 8 | Graphiti missing `neo4j_password` — template newlines | `{{- end -}}{{- with ...` strips the newline between env vars, concatenating them | Medium |
| 9 | Graphiti Docker image doesn't support FalkorDB | Known upstream bug [#749](https://github.com/getzep/graphiti/issues/749), not documented in compose reference | High |
| 10 | Consul service name mismatch (`neo4j-bolt` vs `neo4j`) | Graphiti template assumed a name that didn't match the actual registration | Low |

---

## Recommended Skill Updates

### 1. `octant-autodeploy/SKILL.md` — Add "Rootless Permission Patterns" section

The current skill only has a one-liner about `meta.rootless = "false"` for root containers. It needs a decision tree for the common case where containers expect to run as root but don't need host privileges. Add after the "Advanced Patterns" section:

```markdown
### Rootless Container Permission Decision Tree

When a container fails with "Permission denied" in rootless mode:

1. **Check what user the container runs as** (`USER` in Dockerfile)
2. **Check what paths it accesses** (entrypoint, config dirs)

| Scenario | Fix | Example |
|----------|-----|---------|
| Image has `USER root` or no USER | Works as-is on rootless | Most images |
| Image has `USER app` but entrypoint in `/root/` | Add `user = "root"` to task | Graphiti (`uv` in `/root/.local/bin/`) |
| Image has `USER app` and writes to `/data/` | `user = "2000:2000"` + `userns = "keep-id"` | Grafana, Jellyfin |
| Image needs specific UID (e.g., 472) | `userns = "keep-id:uid=472,gid=472"` | Grafana |
| Image needs real host root (devices, ports <1024) | `meta.rootless = "false"` | Home Assistant |

**Key insight**: `user = "root"` on a rootless agent is SAFE —
container "root" maps to the hashi user (UID 2000) on the host.
This is the preferred fix for images with broken USER/entrypoint combos.

**Pre-flight check** — Before deploying, inspect the image:

```bash
podman pull <image>
podman inspect <image> | jq '.[0].Config.User'
podman inspect <image> | jq '.[0].Config.Entrypoint'
```

If `User` is non-root and `Entrypoint` references paths under `/root/`,
add `user = "root"` to the Nomad task.
```

---

### 2. `octant-autodeploy/SKILL.md` — Fix volume creation instructions

The skill references `make deploy-role ROLE=volumes` but the `volumes` role is not tagged in `octant.yml`. Update the "Phase 1: Prerequisites" section and the volumes-related instructions:

**Current (wrong):**
```bash
make deploy-role ROLE=volumes
```

**Should be:**
```bash
# Use the dedicated volumes playbook:
ansible-playbook playbooks/05-deploy-volumes.yml \
  -i inventory/provisioned_vms.yml -i inventory/groups.yml
```

Also add a note about CephFS propagation:

```markdown
**CephFS propagation note**: After volume creation, CephFS may take
a few seconds to propagate new directories to all nodes. If a Nomad
allocation fails immediately with "no such file or directory", it will
self-heal on the next automatic reschedule attempt.
```

---

### 3. `octant-autodeploy/SKILL.md` — Add Nomad template newline gotcha

Add to the "Key Lessons Learned" section:

```markdown
## 7. Nomad Template Newline Gotcha

When using multiple `{{- with nomadVar ... -}}` blocks in a single template,
be careful with Go template trim markers (`-`). Using `-}}` on `end` AND
`{{-` on the next `with` strips the newline between env vars, concatenating
them into a single line that Nomad can't parse.

### WRONG — env vars concatenated on one line:

```hcl
template {
  data = <<EOT
{{- with nomadVar "nomad/jobs/foo" -}}
VAR_A={{ .value_a }}
{{- end -}}
{{- with nomadVar "nomad/jobs/bar" -}}
VAR_B={{ .value_b }}
{{- end -}}
EOT
}
```

Result: `VAR_A=abcVAR_B=xyz` (broken)

### CORRECT — remove trailing trim on `end` to preserve newlines:

```hcl
template {
  data = <<EOT
{{- with nomadVar "nomad/jobs/foo" }}
VAR_A={{ .value_a }}
{{- end }}
{{- with nomadVar "nomad/jobs/bar" }}
VAR_B={{ .value_b }}
{{- end }}
EOT
}
```

Result:
```
VAR_A=abc
VAR_B=xyz
```

**Rule of thumb**: Use `{{-` (left trim) freely, but avoid `-}}` (right trim)
on `end` statements when another block follows that needs to start on a new line.
```

---

### 4. `octant-validation/SKILL.md` — Add `nomad fmt` caveat for templatefile jobs

Add to the "Common Validation Errors" or "Nomad Validation Workflow" section:

```markdown
### Known Limitation: `nomad fmt` with `templatefile()`

`nomad fmt` will ALWAYS fail on `.nomad.hcl` files that use Terraform
`templatefile()` interpolation (e.g., `${dns}`, `${image}`, `${servicename}`).
This is expected — these are Terraform variables, not valid standalone HCL.

**Skip `nomad fmt` for templatefile-based jobs.** Use `terraform validate`
and `terraform plan` instead — they render the template first and validate
the resulting jobspec.

The validation workflow for templatefile jobs should be:

1. `terraform init`
2. `terraform validate` (checks Terraform syntax + template rendering)
3. `terraform plan` (renders template, submits to Nomad for validation)

Do NOT run:
- `nomad fmt` — will always fail on `${var}` interpolations
- `nomad job validate` — requires a rendered jobspec, not a template
```

---

### 5. `octant-autodeploy/SKILL.md` — Add Docker image compatibility pre-check

Add as a new sub-phase between Phase 2 and Phase 3, or as a checklist item in Phase 2:

```markdown
### Phase 2.5: Docker Image Compatibility Check

Before generating configs, verify the image is compatible with the lab:

1. **Check Dockerfile USER directive** — if non-root, verify the entrypoint
   binary is accessible by that user (not in `/root/`)
2. **Check documented vs actual backend support** — some images document
   support for backends (e.g., FalkorDB) that aren't actually included in
   the Docker image. Verify by checking the image's GitHub issues.
3. **Check for JVM/heavy runtimes** — allocate adequate memory:
   - JVM apps (Neo4j, Elasticsearch): 1024MB+ (heap + metaspace)
   - Python ML apps: 512MB+
   - Go/static apps: 256MB
4. **Check for port conflicts** — if the image uses common ports (6379, 5432, 3306),
   Nomad network namespacing handles isolation, but Consul service names must be unique.

Quick inspection commands:
```bash
podman pull <image>
podman inspect <image> | jq '.[0].Config.User'         # Check USER
podman inspect <image> | jq '.[0].Config.Entrypoint'    # Check entrypoint
podman inspect <image> | jq '.[0].Config.ExposedPorts'  # Check ports
```
```

---

### 6. `octant-volumes/SKILL.md` — Fix playbook reference

Update the "Adding Volumes Workflow" section. The skill currently references a generic
Ansible command that may not match the actual playbook structure.

**Update to:**

```markdown
### Creating Volumes

After adding entries to `inventory/groups.yml`, run the dedicated volumes playbook:

```bash
ansible-playbook playbooks/05-deploy-volumes.yml \
  -i inventory/provisioned_vms.yml -i inventory/groups.yml
```

**Important**: Do NOT use `make deploy-role ROLE=volumes` — the `volumes` role
is not included in `octant.yml` and won't be executed. Always use the dedicated
playbook at `playbooks/05-deploy-volumes.yml`.

**CephFS propagation**: Volumes are created on one node and propagate via CephFS
to all others. This usually takes 1-5 seconds. If a Nomad job starts before
propagation completes, the allocation will fail with "no such file or directory"
but will automatically reschedule and succeed once the directory is visible.
```

---

### 7. `octant-autodeploy/SKILL.md` — Add Consul service name convention

Add to the "Key Lessons Learned" section or as a new subsection under the
service registration template:

```markdown
## 8. Consul Service Name Convention

When referencing services in Nomad templates using `{{ range service "..." }}`,
you must use the exact `name` field from the target service's Nomad job spec.
Do NOT assume a naming convention — always verify.

**Common pattern in this lab:**
- Primary port: `name = "${servicename}"` (e.g., `neo4j`, `falkordb`, `redis`)
- Secondary ports: `name = "${servicename}-<qualifier>"` (e.g., `neo4j-ui`, `nats-monitoring`, `falkordb-ui`)

**Verification:**
```bash
consul catalog services | grep <name>
```

**Example — Graphiti connecting to Neo4j:**

The Neo4j job registers its Bolt port as `neo4j` (not `neo4j-bolt`):
```hcl
service {
  name = "${servicename}"   # Resolves to "neo4j"
  port = "bolt"
}
```

So the Graphiti template must use:
```hcl
{{ range service "neo4j" -}}
NEO4J_URI=bolt://{{ .Address }}:{{ .Port }}
{{- end }}
```

NOT `{{ range service "neo4j-bolt" }}` — this would silently produce
an empty result, leaving the env var unset.
```

---

### 8. `octant-autodeploy/SKILL.md` — Update Enhanced Validation Checklist

Add these items to the existing "Before deploying" checklist:

```markdown
- [ ] **User/Permission Check**: Inspected image USER and entrypoint;
      added `user = "root"` if entrypoint is under `/root/` with non-root USER
- [ ] **Template Newlines**: Verified multi-block Nomad templates preserve
      newlines between env vars (no `-}}` right-trim before next `{{- with`)
- [ ] **Consul Service Names**: Verified `{{ range service "..." }}` references
      match actual service registration names (check with `consul catalog services`)
- [ ] **Image Backend Support**: Confirmed Docker image supports the intended
      backend (check GitHub issues for compatibility gaps)
```

---

## Summary of Changes by File

| File | Changes |
|------|---------|
| `octant-autodeploy/SKILL.md` | Add rootless permission decision tree, fix volume creation command, add template newline gotcha, add image pre-check phase, add Consul naming convention, update validation checklist |
| `octant-validation/SKILL.md` | Add `nomad fmt` caveat for templatefile jobs |
| `octant-volumes/SKILL.md` | Fix playbook reference to `playbooks/05-deploy-volumes.yml`, add CephFS propagation note |
| `octant-autodeploy/patterns/user-namespace.md` | Add `user = "root"` pattern for broken USER/entrypoint images |
