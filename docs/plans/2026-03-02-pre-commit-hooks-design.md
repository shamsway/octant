# Pre-Commit Hooks - Design

**Date:** 2026-03-02
**Branch:** `feature/octant-virtual-cluster`
**Status:** Approved

## Goal

Add pre-commit hooks for secrets scanning, linting, and code quality checks before pushing to GitHub.

## Context

The Octant repo has no automated quality gates. It contains secrets references (1Password tokens, Cloudflare API keys), diverse file types (HCL, YAML, Bash, Python, Markdown), and is being prepared for its first push to GitHub. Pre-commit hooks catch issues before they enter version control.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Framework | pre-commit (pre-commit.com) | Industry standard, declarative YAML config, manages tool versions |
| Secrets scanner | gitleaks | Low false positives, single binary, active maintenance |
| YAML linting | yamllint (non-Ansible) + ansible-lint (Ansible files) | Avoids double-reporting; ansible-lint embeds yamllint |
| Shell linting | shellcheck via local hook | Avoids Docker dependency; system-installed shellcheck is simpler |
| Markdown linting | markdownlint-cli | Simpler than markdownlint-cli2 for this use case |
| Python formatting | black + flake8 | Standard pairing; only 2 Python files in repo |
| Terraform/HCL linting | Skipped | Embedded Nomad `$${var}` syntax breaks terraform fmt/validate |

## What Gets Changed

| Component | Current State | Target State | Notes |
|-----------|--------------|--------------|-------|
| `.pre-commit-config.yaml` | Does not exist | Hook definitions for all tools | New file |
| `.gitleaks.toml` | Does not exist | IaC allowlist for false positives | New file |
| `.yamllint.yml` | Does not exist | Relaxed profile, 160-char lines | New file |
| `.ansible-lint` | Does not exist | Production profile, path exclusions | New file |
| `.markdownlint.json` | Does not exist | Disable line-length, inline HTML | New file |
| `docs/pre-commit-hooks.md` | Does not exist | Setup, testing, override docs | New file |

## Section 1: Pre-Commit Configuration

`.pre-commit-config.yaml` with these hook groups (in execution order):

1. **pre-commit-hooks** (standard) - trailing whitespace, EOF fixer, merge conflict detection, large file check, private key detection, YAML syntax check (`--unsafe` for Ansible tags)
2. **gitleaks** - secrets scanning with `.gitleaks.toml` config
3. **yamllint** - YAML style checking, excluding Ansible paths
4. **ansible-lint** - Ansible best practices (includes embedded yamllint)
5. **shellcheck** - local hook using system-installed shellcheck
6. **markdownlint-cli** - Markdown formatting
7. **black** - Python auto-formatting
8. **flake8** - Python linting (max-line-length=88 to match black)

## Section 2: Gitleaks Configuration

`.gitleaks.toml` allowlist patterns:
- Terraform variable references (`${var.foo}`)
- Nomad runtime references (`$${NOMAD_META}`)
- Image digest patterns, font files, lock files
- Terraform state files (should never be committed)

Inline suppression: `# gitleaks:allow` on any line with a known false positive.

## Section 3: Linting Configurations

**`.yamllint.yml`**: Extends `relaxed` profile. 160-char line length (warning, not error). Truthy values allow `yes`/`no`. Excludes Ansible paths to avoid conflict with ansible-lint.

**`.ansible-lint`**: Production profile. Excludes `.cache/`, `.github/`, `local/`, `terraform/`. Warns on line-length and name casing rather than failing.

**`.markdownlint.json`**: Disables MD013 (line-length), MD033 (inline HTML), MD041 (first heading H1).

## Section 4: Documentation

`docs/pre-commit-hooks.md` covering:
- Prerequisites and installation steps
- How to run all checks locally (individually and all at once)
- Override procedures (skip all, skip specific, inline suppression)
- Troubleshooting common issues
- How to update hook versions

## Non-Goals

- Terraform/HCL linting (broken by Nomad variable embedding)
- GitHub Actions CI (separate effort)
- Enforcing hooks on CI/CD (local-only for now)

## Validation

```bash
# Install and run all hooks
pip install pre-commit
pre-commit install
pre-commit run --all-files

# Run individual hooks
pre-commit run gitleaks --all-files
pre-commit run yamllint --all-files
pre-commit run ansible-lint --all-files
pre-commit run shellcheck --all-files
pre-commit run markdownlint --all-files
```

All hooks should pass (or produce only warnings) on the current codebase before committing.
