# Pre-Commit Hooks

This repo uses [pre-commit](https://pre-commit.com/) to enforce code quality and catch issues before they reach the repository.

## Overview

The following hooks are configured in `.pre-commit-config.yaml`:

| Hook | Source | Purpose |
|------|--------|---------|
| `trailing-whitespace` | pre-commit-hooks | Remove trailing whitespace |
| `end-of-file-fixer` | pre-commit-hooks | Ensure files end with a newline |
| `check-yaml` | pre-commit-hooks | Basic YAML syntax validation |
| `check-merge-conflict` | pre-commit-hooks | Detect unresolved merge conflict markers |
| `check-added-large-files` | pre-commit-hooks | Block files over 500KB |
| `detect-private-key` | pre-commit-hooks | Detect accidentally committed private keys |
| `gitleaks` | gitleaks | Secrets scanning (hardcoded credentials, API keys, tokens) |
| `yamllint` | yamllint | YAML formatting rules (non-Ansible files) |
| `ansible-lint` | ansible-lint | Ansible best practices + embedded YAML linting for Ansible files |
| `shellcheck` | shellcheck | Shell script bug detection |
| `markdownlint` | markdownlint-cli | Markdown formatting |
| `black` | black | Python auto-formatting |
| `flake8` | flake8 | Python linting |

## Prerequisites

- **Python 3.8+**: Required for pre-commit and ansible-lint
- **pre-commit**: `pip install pre-commit`
- **shellcheck**: Installed separately (not managed by pre-commit)
  - Debian/Ubuntu: `sudo apt-get install shellcheck`
  - macOS: `brew install shellcheck`
- **Node.js**: Required for markdownlint-cli — installed automatically by pre-commit

## Setup

```bash
# Install the pre-commit framework
pip install pre-commit

# Install hooks into this repo's git config
pre-commit install

# Verify by running all hooks
pre-commit run --all-files
```

## Running Locally

```bash
# Run ALL hooks on ALL files (full validation)
pre-commit run --all-files

# Run ALL hooks on staged files only (what a commit does)
pre-commit run

# Run a specific hook on all files
pre-commit run gitleaks --all-files
pre-commit run yamllint --all-files
pre-commit run ansible-lint --all-files
pre-commit run shellcheck --all-files
pre-commit run markdownlint --all-files
pre-commit run black --all-files
pre-commit run flake8 --all-files

# Run a specific hook on specific files
pre-commit run yamllint --files path/to/file.yml
pre-commit run shellcheck --files scripts/myscript.sh
```

## Override Procedures

Bypassing hooks should be reserved for genuine emergencies. Prefer fixing the underlying issue or using per-hook skips over blanket `--no-verify`.

```bash
# Skip ALL hooks for a single commit (emergency use)
git commit --no-verify -m "message"
# Short form:
git commit -n -m "message"

# Skip specific hook(s) for a single commit
SKIP=gitleaks git commit -m "message"
SKIP=gitleaks,ansible-lint git commit -m "message"
SKIP=markdownlint,yamllint git commit -m "message"
```

## Inline Suppressions

Use these when a specific line triggers a false positive and a skip-on-commit is too broad.

| Tool | Syntax | Placement |
|------|--------|-----------|
| gitleaks | `# gitleaks:allow` | End of the offending line |
| yamllint | `# yamllint disable-line rule:line-length` | End of the offending line |
| shellcheck | `# shellcheck disable=SC2086` | Line above the offending line |
| markdownlint | `<!-- markdownlint-disable MD013 -->` | In the markdown file |
| flake8 | `# noqa: E501` | End of the offending line |

## Updating Hooks

```bash
# Update all hooks to latest versions
pre-commit autoupdate

# Update a specific hook repository
pre-commit autoupdate --repo https://github.com/gitleaks/gitleaks

# Clear pre-commit cache (if hooks misbehave)
pre-commit clean
```

## Configuration Files

| File | Purpose |
|------|---------|
| `.pre-commit-config.yaml` | Hook definitions and versions |
| `.gitleaks.toml` | Secrets scanning allowlist |
| `.yamllint.yml` | YAML lint rules |
| `.ansible-lint` | Ansible lint profile and exclusions |
| `.markdownlint.json` | Markdown lint rules |

## Troubleshooting

- **shellcheck not found**: shellcheck is a system dependency, not managed by pre-commit. Install with `sudo apt-get install shellcheck` (Debian/Ubuntu) or `brew install shellcheck` (macOS).
- **ansible-lint Python version error**: Ensure `language_version: python3` is set for the ansible-lint hook in `.pre-commit-config.yaml`.
- **Hooks not running on commit**: Run `pre-commit install` to re-install the git hook scripts.
- **False positive from gitleaks**: Add `# gitleaks:allow` to the end of the line, or add an allowlist pattern to `.gitleaks.toml`.
- **YAML parse errors on template files**: Add the file path to the `exclude` pattern for the relevant hook in `.pre-commit-config.yaml`.

## What Is NOT Linted

Some file types and directories are intentionally excluded:

- **Terraform/HCL files**: Nomad variable embedding (`$${var}`) is not valid HCL syntax, which breaks `terraform fmt` and `terraform validate`.
- **Packer templates**: Template variable syntax (`${var}`) is not valid YAML.
- **`local/` directory**: Gitignored and contains local-only projects not subject to repo standards.
- **Some Ansible roles and playbooks**: Excluded from ansible-lint due to missing collection dependencies (`ansible.posix`, `community.libvirt`) that are not installed in the pre-commit virtualenv.
