# Pre-Commit Hooks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add pre-commit hooks for secrets scanning, YAML/Ansible/shell/markdown/Python linting, and document setup + override procedures.

**Architecture:** Uses the `pre-commit` framework (pre-commit.com) with a `.pre-commit-config.yaml` defining 8 hook groups. Each tool has its own config file. Documentation lives at `docs/pre-commit-hooks.md`.

**Tech Stack:** pre-commit framework, gitleaks, yamllint, ansible-lint, shellcheck, markdownlint-cli, black, flake8

---

### Task 1: Create gitleaks configuration

**Files:**
- Create: `.gitleaks.toml`

**Step 1: Create `.gitleaks.toml`**

```toml
title = "Octant Homelab gitleaks config"

[allowlist]
description = "IaC false positive allowlist"

paths = [
  '''\.tfstate(\.backup)?$''',
  '''(?i)\.(jpg|jpeg|png|gif|svg|ico)$''',
  '''(?i)\.(eot|[ot]tf|woff2?)$''',
  '''node_modules/''',
  '''\.terraform/''',
]
```

**Step 2: Commit**

```bash
git add .gitleaks.toml
git commit -m "chore: add gitleaks configuration for secrets scanning"
```

---

### Task 2: Create yamllint configuration

**Files:**
- Create: `.yamllint.yml`

**Step 1: Create `.yamllint.yml`**

```yaml
---
extends: relaxed

ignore: |
  .terraform/
  node_modules/
  local/
  .worktrees/

rules:
  line-length:
    max: 160
    level: warning
    allow-non-breakable-words: true
    allow-non-breakable-inline-mappings: true
  truthy:
    allowed-values: ['true', 'false', 'yes', 'no']
    check-keys: false
    level: warning
  comments:
    min-spaces-from-content: 1
  indentation:
    spaces: 2
    indent-sequences: true
    check-multi-line-strings: false
  empty-lines:
    max: 2
    max-start: 1
    max-end: 1
```

**Step 2: Commit**

```bash
git add .yamllint.yml
git commit -m "chore: add yamllint configuration"
```

---

### Task 3: Create ansible-lint configuration

**Files:**
- Create: `.ansible-lint`

**Step 1: Create `.ansible-lint`**

```yaml
---
profile: moderate

exclude_paths:
  - .cache/
  - .github/
  - .worktrees/
  - local/
  - terraform/
  - packer/
  - node_modules/
  - docs/

warn_list:
  - yaml[line-length]
  - name[casing]
  - name[missing]

skip_list: []
```

Note: Use `moderate` profile rather than `production` to avoid noisy failures on an existing codebase. Can tighten later.

**Step 2: Commit**

```bash
git add .ansible-lint
git commit -m "chore: add ansible-lint configuration"
```

---

### Task 4: Create markdownlint configuration

**Files:**
- Create: `.markdownlint.json`

**Step 1: Create `.markdownlint.json`**

```json
{
  "default": true,
  "MD013": false,
  "MD033": false,
  "MD041": false
}
```

- `MD013`: Disable line-length (IaC docs have long code blocks/URLs)
- `MD033`: Disable inline HTML check (used in some README tables)
- `MD041`: Disable first-line-must-be-H1 (not all docs start with H1)

**Step 2: Commit**

```bash
git add .markdownlint.json
git commit -m "chore: add markdownlint configuration"
```

---

### Task 5: Create pre-commit configuration

**Files:**
- Create: `.pre-commit-config.yaml`

**Step 1: Create `.pre-commit-config.yaml`**

```yaml
---
repos:
  # Standard hooks - whitespace, merge conflicts, large files, basic checks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
        args: [--unsafe]
        exclude: ^(local/|\.worktrees/)
      - id: check-merge-conflict
      - id: check-added-large-files
        args: [--maxkb=500]
      - id: detect-private-key

  # Secrets scanning
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks

  # YAML linting (non-Ansible files only - ansible-lint handles Ansible YAML)
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.35.1
    hooks:
      - id: yamllint
        args: [-c, .yamllint.yml]
        exclude: ^(roles/|playbooks/|handlers/|inventory/|local/|\.worktrees/)

  # Ansible linting (includes embedded yamllint for Ansible files)
  - repo: https://github.com/ansible/ansible-lint
    rev: v25.1.3
    hooks:
      - id: ansible-lint
        additional_dependencies:
          - ansible-core>=2.17

  # Shell script linting
  - repo: local
    hooks:
      - id: shellcheck
        name: shellcheck
        entry: shellcheck
        language: system
        types: [shell]
        exclude: ^(local/|\.worktrees/|node_modules/)
        args: [--severity=warning]

  # Markdown linting
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.43.0
    hooks:
      - id: markdownlint
        args: [--config, .markdownlint.json]
        exclude: ^(local/|\.worktrees/|node_modules/)

  # Python formatting
  - repo: https://github.com/psf/black-pre-commit-mirror
    rev: 24.10.0
    hooks:
      - id: black
        types: [python]
        exclude: ^(local/|\.worktrees/|node_modules/)

  # Python linting
  - repo: https://github.com/PyCQA/flake8
    rev: 7.1.1
    hooks:
      - id: flake8
        args: [--max-line-length=88, --extend-ignore=E203]
        types: [python]
        exclude: ^(local/|\.worktrees/|node_modules/)
```

Note on versions: Use `pre-commit autoupdate` after initial install to get the latest pinned tags. The versions above are known-stable as of early 2026. The exact latest tags will be resolved during implementation by running `pre-commit autoupdate`.

**Step 2: Commit**

```bash
git add .pre-commit-config.yaml
git commit -m "chore: add pre-commit hook configuration"
```

---

### Task 6: Install and run hooks, fix issues

**Step 1: Install pre-commit**

```bash
pip install pre-commit
```

**Step 2: Update hook versions to latest**

```bash
pre-commit autoupdate
```

This updates `rev:` values in `.pre-commit-config.yaml` to the latest available tags.

**Step 3: Install hooks into git**

```bash
pre-commit install
```

**Step 4: Run all hooks on all files**

```bash
pre-commit run --all-files
```

Expected: Some hooks may fail on existing files (trailing whitespace, EOF, yamllint warnings). The auto-fixers (trailing-whitespace, end-of-file-fixer, black) will modify files in-place.

**Step 5: Review auto-fixed changes**

```bash
git diff
```

Review what the auto-fixers changed. Stage and commit if the changes look correct.

**Step 6: Fix any remaining lint issues**

For each failing hook, fix the issues or add targeted exclusions/suppressions:
- yamllint failures: Fix or add `# yamllint disable-line` comments
- ansible-lint failures: Fix or add to `skip_list` / `warn_list` in `.ansible-lint`
- shellcheck failures: Fix or add `# shellcheck disable=SCXXXX` comments
- markdownlint failures: Fix or add rules to `.markdownlint.json`
- gitleaks false positives: Add `# gitleaks:allow` inline or extend `.gitleaks.toml` allowlist

**Step 7: Run hooks again to confirm all pass**

```bash
pre-commit run --all-files
```

Expected: All hooks pass (warnings are OK, errors are not).

**Step 8: Commit all fixes**

```bash
git add -A
git commit -m "chore: fix lint issues found by pre-commit hooks"
```

---

### Task 7: Write documentation

**Files:**
- Create: `docs/pre-commit-hooks.md`

**Step 1: Create `docs/pre-commit-hooks.md`**

The documentation must cover:

1. **Overview** - What hooks are configured and why
2. **Prerequisites** - What tools to install (`pre-commit`, `shellcheck`)
3. **Setup** - `pip install pre-commit && pre-commit install`
4. **Running locally** - Commands to run all hooks or specific hooks
5. **Override procedures** - How to skip hooks when needed
6. **Inline suppressions** - Per-tool suppression comment syntax
7. **Updating hooks** - How to bump versions
8. **Troubleshooting** - Common issues and fixes

Include these specific examples:

```bash
# Install pre-commit framework
pip install pre-commit

# Install hooks into this repo's git config
pre-commit install

# Run ALL hooks on ALL files (full validation)
pre-commit run --all-files

# Run ALL hooks on staged files only (what commit does)
pre-commit run

# Run a specific hook on all files
pre-commit run gitleaks --all-files
pre-commit run yamllint --all-files
pre-commit run ansible-lint --all-files
pre-commit run shellcheck --all-files
pre-commit run markdownlint --all-files
pre-commit run black --all-files
pre-commit run flake8 --all-files

# Skip ALL hooks for a single commit
git commit --no-verify -m "message"
# or
git commit -n -m "message"

# Skip specific hook(s) for a single commit
SKIP=gitleaks git commit -m "message"
SKIP=gitleaks,ansible-lint git commit -m "message"

# Update all hooks to latest versions
pre-commit autoupdate
```

**Step 2: Commit**

```bash
git add docs/pre-commit-hooks.md
git commit -m "docs: add pre-commit hooks setup and usage guide"
```

---

### Task 8: Final validation

**Step 1: Clean run of all hooks**

```bash
pre-commit run --all-files
```

Expected: All pass.

**Step 2: Test override procedure**

```bash
echo "test" > /tmp/test-override.txt
SKIP=gitleaks git commit --dry-run
```

Verify SKIP works as documented.

**Step 3: Commit any remaining changes**

```bash
git add .pre-commit-config.yaml  # in case autoupdate changed versions
git commit -m "chore: finalize pre-commit hook versions"
```
