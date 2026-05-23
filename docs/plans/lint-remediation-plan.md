# Lint Remediation Plan

Generated: 2026-03-02

## Summary (with `docs/` excluded from linting)

| Linter | Status | Issues | Notes |
|--------|--------|--------|-------|
| YAML lint | FAIL | 22 errors, 2 warnings | Trailing spaces, missing newlines in root-level and terraform YAML |
| Ansible lint | FAIL | 12 errors, 3 warnings | 12x missing newline at EOF, 2x name casing, 1x line length |
| Shellcheck | PASS | 0 | Clean |
| Markdownlint | FAIL | 30 issues | Trailing spaces (MD009) and missing final newlines (MD047) in README files |
| Black (Python) | FAIL | 3 files | `terraform/gcp/preempt-notify.py`, `packer/files/debian-init.py`, `scripts/state-to-markdown.py` |
| Flake8 (Python) | FAIL | 4 issues | All in `terraform/gcp/preempt-notify.py` (blank lines, no newline) |
| Gitleaks | SKIPPED | N/A | Not installed — requires Go binary, install separately |

**Note:** `docs/` is excluded from all linters except ansible-lint (which already excludes it via `.ansible-lint`). Legacy code examples in `docs/` are not linted.

## Phase 1: Bulk Whitespace & Newline Fixes (low risk, high volume)

The majority of issues across all linters are two patterns:
- **Trailing whitespace**
- **Missing final newline**

These can be fixed in bulk safely:

```bash
# Fix trailing whitespace in all tracked files (excluding binary files)
git ls-files | grep -vE '\.(png|jpg|gif|ico|eot|otf|ttf|woff|woff2|tfstate)$' | xargs sed -i 's/[[:space:]]*$//'

# Add missing final newlines
git ls-files | grep -vE '\.(png|jpg|gif|ico|eot|otf|ttf|woff|woff2|tfstate)$' | while read f; do
  [ -s "$f" ] && [ "$(tail -c1 "$f" | xxd -p)" != "0a" ] && echo >> "$f"
done
```

**Affected linters:** yamllint, ansible-lint, markdownlint, flake8

## Phase 2: Python Formatting (auto-fixable)

Run `black` to auto-format 3 Python files:

```bash
black packer/files/debian-init.py \
      scripts/state-to-markdown.py \
      terraform/gcp/preempt-notify.py
```

This will fix all black issues and all flake8 issues (E302, E305, W292).

## Phase 3: Ansible Lint (manual, 2 items)

After Phase 1 fixes the 12 EOF issues, only 2 warnings remain:

1. `playbooks/02-deploy-ceph.yml:39` — `name[casing]`: rename handler `restart sshd` → `Restart sshd`
2. `playbooks/02.5-deploy-haproxy.yml:21` — `name[casing]`: rename handler `restart haproxy` → `Restart haproxy`

**Note:** These are warnings, not errors. Could also suppress in `.ansible-lint` skip_list.

## Phase 4: Ansible Lint Config Fix

Ansible-lint warns about `.yamllint.yml` incompatibility:
> `octal-values.forbid-implicit-octal` and `octal-values.forbid-explicit-octal` must be true

Add to `.yamllint.yml`:
```yaml
rules:
  octal-values:
    forbid-implicit-octal: true
    forbid-explicit-octal: true
```

## Phase 5: Install Gitleaks

Gitleaks is a Go binary. Install options:
```bash
# Option A: Download release binary
curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.30.0/gitleaks_8.30.0_linux_x64.tar.gz | tar xz -C /usr/local/bin gitleaks

# Option B: Go install
go install github.com/gitleaks/gitleaks/v8@v8.30.0
```

Then run: `gitleaks detect --config .gitleaks.toml --source .`

## Execution Order

1. Phase 1 (bulk whitespace/newline) — resolves ~80% of all issues across all linters
2. Phase 2 (`black` auto-format) — resolves remaining Python issues
3. Phase 3 (2 ansible handler names) — trivial manual fix or suppress
4. Phase 4 (yamllint octal config) — one-line config addition
5. Phase 5 (gitleaks install + run) — separate tooling step

## Files with Issues (complete list)

### YAML files (yamllint errors — 22 errors, 2 warnings)
- `reset-consul.yml` — 3x trailing spaces, no newline
- `reset-nomad.yml` — trailing space
- `start-consul.yml` — trailing space
- `start-nomad.yml` — trailing space
- `stop-consul.yml` — no newline
- `stop-nomad.yml` — no newline
- `terraform/litellm/config.yaml` — truthy warning
- `update-consul-configs.yml` — 4x trailing spaces, no newline
- `update-nfs-mounts.yml` — no newline
- `update-nomad-configs.yml` — 4x trailing spaces, no newline
- `update-nomad-root-agents.yml` — trailing space, line length warning

### Ansible files (ansible-lint — 12 errors, 3 warnings)
- `reset-consul.yml` — no newline
- `roles/consul-server/tasks/main.yml` — no newline
- `roles/docker/defaults/main.yml` — no newline
- `roles/nomad-agent-root/defaults/main.yml` — no newline
- `roles/nomad-agent-root/tasks/main.yml` — no newline
- `roles/podman-root/tasks/main.yml` — no newline
- `roles/restic/tasks/main.yml` — no newline
- `stop-consul.yml` — no newline
- `stop-nomad.yml` — no newline
- `update-consul-configs.yml` — no newline
- `update-nfs-mounts.yml` — no newline
- `update-nomad-configs.yml` — no newline
- `playbooks/02-deploy-ceph.yml:39` — name casing warning
- `playbooks/02.5-deploy-haproxy.yml:21` — name casing warning
- `update-nomad-root-agents.yml:33` — line length warning

### Markdown files (markdownlint — 30 issues)
- `README.md` — 3x trailing spaces, no newline
- `inventory/README.md` — no newline
- `terraform/backups/README.md` — 2x trailing spaces, no newline
- `terraform/chromadb/README.md` — no newline
- `terraform/consul/README.md` — no newline
- `terraform/dns/README.md` — no newline
- `terraform/grafana/README.md` — no newline
- `terraform/homeassitant/README.md` — trailing space
- `terraform/jupyter/README.md` — no newline
- `terraform/langfuse/README.md` — no newline
- `terraform/librenms/README.md` — no newline
- `terraform/litellm/README.md` — no newline
- `terraform/loki/README.md` — no newline
- `terraform/open-webui/README.md` — no newline
- `terraform/plantuml/README.md` — no newline
- `terraform/postgres-backup/README.md` — no newline
- `terraform/prometheus/README.md` — no newline
- `terraform/restic/README.md` — trailing space, no newline
- `terraform/template/README.md` — no newline
- `terraform/traefik/README.md` — no newline
- `terraform/unifi/README.md` — trailing space, no newline
- `terraform/weaviate/README.md` — no newline
- `terraform/whoami/README.md` — no newline

### Python files (black + flake8 — 3 files, 4 flake8 issues)
- `packer/files/debian-init.py` — black formatting (quotes, line wrapping, docstring indent)
- `scripts/state-to-markdown.py` — black formatting (line wrapping)
- `terraform/gcp/preempt-notify.py` — black formatting + flake8 (blank lines, no newline)
