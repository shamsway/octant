# Secrets Naming Standardization - Design

**Date:** 2026-02-24
**Branch:** `feature/app-migration`
**Scope:** Code-only rename; targets fresh `make rebuild-clean`

## Goal

Standardize all 1Password secret names to follow the `{category}_{service}_{type}_{identifier}` convention documented in `octant-private/docs/secrets/README.md`. Eliminate the 7 inconsistent naming patterns currently in use (Title Case, Title Case with spaces, URL-style, bare names, etc.).

## Naming Convention

| Category | Format | Example |
|----------|--------|---------|
| API keys/tokens | `api_{service}_key` | `api_anthropic_key` |
| Service credentials | `service_{name}` | `service_postgres` |
| Database user creds | `db_{service}` | `db_litellm` |
| Backup passwords | `backup_{service}_password` | `backup_restic_password` |

## Complete Rename Mapping

### Secrets That Need Renaming

| Current Title | New Title | Category | Used By (terraform modules) |
|---|---|---|---|
| `Postgres` | `service_postgres` | service | postgres, backups, pgadmin |
| `litellm` | `service_litellm` | service | litellm, open-webui, openclaw-gateway |
| `Registry` | `service_registry` | service | (seed only) |
| `Restic` | `backup_restic_password` | misc | restic |
| `Backblaze` | `api_backblaze_creds` | api | restic |
| `Cloudflare` | `api_cloudflare_dns_token` | api | (seed script only) |
| `Nautobot` | `service_nautobot` | service | nautobot |
| `nautobot_db` | `db_nautobot` | db | nautobot |
| `postgres_litellm` | `db_litellm` | db | litellm |
| `postgres_n8n` | `db_n8n` | db | n8n |
| `postgres_phoenix` | `db_phoenix` | db | phoenix (already correct!) |
| `postgres_langfuse` | `db_langfuse` | db | langfuse |
| `service_n8n` / `n8n_admin` | `service_n8n` | service | n8n |
| `OpenAI API Key` | `api_openai_key` | api | litellm |
| `Anthropic API Key` | `api_anthropic_key` | api | litellm (merge with openclaw's copy) |
| `Replicate API Key` | `api_replicate_key` | api | litellm |
| `Openrouter API Key` | `api_openrouter_key` | api | litellm |
| `Cohere API Key` | `api_cohere_key` | api | litellm |
| `Groq API Key` | `api_groq_key` | api | litellm |
| `Langfuse API Key` | `api_langfuse_key` | api | litellm |

### Secrets Already Correctly Named (No Change)

`service_mariadb`, `service_openclaw`, `db_phoenix`, `api_openclaw_discord`, `api_openclaw_slack_bot`, `api_openclaw_slack_app`, `api_openclaw_op_sa`, `api_moonshot_key`, `api_zai_key`, `api_sendgrid_key`

### Key Merges

1. **`litellm` + `service_litellm`** (openclaw-gateway) -> single `service_litellm`
   - Both reference the same LiteLLM admin credentials (username + password)
   - litellm/main.tf and open-webui/main.tf currently use title `litellm`
   - openclaw-gateway/main.tf already uses title `service_litellm`
   - After rename, all three modules reference the same `service_litellm` item

2. **`Anthropic API Key` + `api_anthropic_key`** -> single `api_anthropic_key`
   - Currently two separate 1Password items with the same API key value
   - litellm/main.tf uses `Anthropic API Key`, openclaw-gateway uses `api_anthropic_key`
   - After rename, both reference the same `api_anthropic_key` item

3. **`service_n8n` + `n8n_admin`** -> single `service_n8n`
   - Both are n8n service credentials

## Files to Modify

### 4 Sources of Truth

1. **`roles/seed-onepassword/defaults/main.yml`** - update all titles in `op_seed_items` and `op_optional_items`
2. **`scripts/clear-vault-secrets.sh`** - update `SEEDED_ITEMS` and `OPTIONAL_ITEMS` arrays
3. **`scripts/seed-1password-vault.sh`** - update all `create_item` call titles
4. **`scripts/generate-secrets.sh`** - review for any secret name references

### Terraform Modules (title field changes)

| Module | Current Title(s) | New Title(s) |
|--------|-----------------|-------------|
| `terraform/postgres/main.tf` | `Postgres` | `service_postgres` |
| `terraform/backups/main.tf` | `Postgres` | `service_postgres` |
| `terraform/pgadmin/main.tf` | `Postgres` | `service_postgres` |
| `terraform/litellm/main.tf` | `litellm`, `postgres_litellm`, `OpenAI API Key`, `Anthropic API Key`, `Replicate API Key`, `Openrouter API Key`, `Cohere API Key`, `Groq API Key`, `Langfuse API Key` | `service_litellm`, `db_litellm`, `api_openai_key`, `api_anthropic_key`, `api_replicate_key`, `api_openrouter_key`, `api_cohere_key`, `api_groq_key`, `api_langfuse_key` |
| `terraform/open-webui/main.tf` | `litellm` | `service_litellm` |
| `terraform/n8n/main.tf` | `postgres_n8n`, `n8n_admin` | `db_n8n`, `service_n8n` |
| `terraform/nautobot/main.tf` | `Nautobot`, `nautobot_db` | `service_nautobot`, `db_nautobot` |
| `terraform/langfuse/main.tf` | `postgres_langfuse` | `db_langfuse` |
| `terraform/restic/main.tf` | `Restic`, `Backblaze` | `backup_restic_password`, `api_backblaze_creds` |
| `terraform/mariadb/main.tf` | `service_mariadb` | (no change) |
| `terraform/phoenix/main.tf` | `db_phoenix` | (no change) |
| `terraform/openclaw-gateway/main.tf` | `service_litellm`, `api_*` | (no change) |
| `terraform/ntfy/main.tf` | `api_sendgrid_key` | (no change) |

### Documentation

- Copy `octant-private/docs/secrets/README.md` into `docs/secrets/README.md` in this repo

## Non-Goals

- No vault migration script (cleared on `rebuild-clean`)
- No addition of secrets for services not yet deployed (YAGNI)
- No changes to the `template/main.tf` placeholder `[replace]`
