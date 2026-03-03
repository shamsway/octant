# Secrets Naming Standardization - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename all 1Password secret references to follow the `{category}_{service}_{type}` convention from the secrets README.

**Architecture:** Pure string replacement across 4 sources of truth (seed role, clear script, seed script, terraform modules). No logic changes. Each task updates one source of truth, then a final verification task confirms consistency.

**Tech Stack:** Ansible (YAML), Bash, Terraform (HCL)

**Reference:** `docs/plans/2026-02-24-secrets-naming-design.md` for the complete rename mapping.

---

### Task 1: Update seed-onepassword role defaults

**Files:**
- Modify: `roles/seed-onepassword/defaults/main.yml`

**Step 1: Update `op_seed_items` titles**

Replace the entire `op_seed_items` list. Changes:
- `Postgres` -> `service_postgres`
- `postgres_litellm` -> `db_litellm`
- `postgres_n8n` -> `db_n8n`
- `postgres_phoenix` -> `db_phoenix`
- `litellm` -> `service_litellm`
- `Registry` -> `service_registry`
- `postgres_langfuse` -> `db_langfuse`
- `Restic` -> `backup_restic_password`

```yaml
op_seed_items:
  - title: "service_postgres"
    category: "login"
    username: "postgres"
  - title: "db_litellm"
    category: "login"
    username: "litellm"
  - title: "db_n8n"
    category: "login"
    username: "n8n"
  - title: "db_phoenix"
    category: "login"
    username: "phoenix"
  - title: "service_mariadb"
    category: "password"
  - title: "service_litellm"
    category: "login"
    username: "admin"
  - title: "service_registry"
    category: "password"
  - title: "db_langfuse"
    category: "login"
    username: "langfuse"
  - title: "backup_restic_password"
    category: "password"
```

**Step 2: Update `op_optional_items` titles**

Replace the entire `op_optional_items` list. Changes:
- `OpenAI API Key` -> `api_openai_key`
- `Anthropic API Key` -> `api_anthropic_key` (already exists, merge)
- `Replicate API Key` -> `api_replicate_key`
- `Openrouter API Key` -> `api_openrouter_key`
- `Cohere API Key` -> `api_cohere_key`
- `Groq API Key` -> `api_groq_key`
- `Langfuse API Key` -> `api_langfuse_key`
- `service_n8n` -> `service_n8n`
- `db_phoenix` -> remove (now in seed list)

```yaml
op_optional_items:
  - title: "api_openai_key"
    used_by: "litellm"
  - title: "api_anthropic_key"
    used_by: "litellm, openclaw-gateway"
  - title: "api_replicate_key"
    used_by: "litellm"
  - title: "api_openrouter_key"
    used_by: "litellm"
  - title: "api_cohere_key"
    used_by: "litellm"
  - title: "api_groq_key"
    used_by: "litellm"
  - title: "api_langfuse_key"
    used_by: "litellm"
  - title: "service_n8n"
    used_by: "n8n"
  - title: "api_openclaw_discord"
    used_by: "openclaw-gateway"
  - title: "api_openclaw_slack_bot"
    used_by: "openclaw-gateway"
  - title: "api_openclaw_slack_app"
    used_by: "openclaw-gateway"
  - title: "api_sendgrid_key"
    used_by: "ntfy"
```

**Step 3: Commit**

```bash
git add roles/seed-onepassword/defaults/main.yml
git commit -m "refactor: rename seed-onepassword secrets to standard convention"
```

---

### Task 2: Update clear-vault-secrets.sh

**Files:**
- Modify: `scripts/clear-vault-secrets.sh`

**Step 1: Update `SEEDED_ITEMS` array (lines 18-28)**

```bash
SEEDED_ITEMS=(
  "service_postgres"
  "db_litellm"
  "db_n8n"
  "db_phoenix"
  "db_langfuse"
  "service_mariadb"
  "service_litellm"
  "service_registry"
  "backup_restic_password"
)
```

**Step 2: Update `OPTIONAL_ITEMS` array (lines 31-46)**

```bash
OPTIONAL_ITEMS=(
  "api_openai_key"
  "api_anthropic_key"
  "api_replicate_key"
  "api_openrouter_key"
  "api_cohere_key"
  "api_groq_key"
  "api_langfuse_key"
  "service_n8n"
  "api_openclaw_discord"
  "api_openclaw_slack_bot"
  "api_openclaw_slack_app"
  "api_sendgrid_key"
)
```

**Step 3: Commit**

```bash
git add scripts/clear-vault-secrets.sh
git commit -m "refactor: rename clear-vault-secrets items to standard convention"
```

---

### Task 3: Update seed-1password-vault.sh

**Files:**
- Modify: `scripts/seed-1password-vault.sh`

**Step 1: Rename all `create_item` titles**

Apply these title changes to the `create_item` calls:

| Line | Current | New |
|------|---------|-----|
| 141 | `"Postgres"` | `"service_postgres"` |
| 147 | `"litellm"` | `"service_litellm"` |
| 152 | `"postgres_litellm"` | `"db_litellm"` |
| 159 | `"Anthropic API Key"` | `"api_anthropic_key"` |
| 163 | `"OpenAI API Key"` | `"api_openai_key"` |
| 166 | `"Replicate API Key"` | `"api_replicate_key"` |
| 169 | `"Openrouter API Key"` | `"api_openrouter_key"` |
| 172 | `"Cohere API Key"` | `"api_cohere_key"` |
| 175 | `"Groq API Key"` | `"api_groq_key"` |
| 181 | `"Langfuse API Key"` | `"api_langfuse_key"` |
| 189 | `"Cloudflare"` | `"api_cloudflare_dns_token"` |
| 194 | `"Registry"` | `"service_registry"` |
| 203 | `"Restic"` | `"backup_restic_password"` |
| 209 | `"Backblaze"` | `"api_backblaze_creds"` |
| 217 | `"Nautobot"` | `"service_nautobot"` |
| 221 | `"nautobot_db"` | `"db_nautobot"` |
| 227 | `"postgres_langfuse"` | `"db_langfuse"` |

**Step 2: Commit**

```bash
git add scripts/seed-1password-vault.sh
git commit -m "refactor: rename seed-1password-vault items to standard convention"
```

---

### Task 4: Update terraform modules — postgres, backups, pgadmin

**Files:**
- Modify: `terraform/postgres/main.tf:31` — `"Postgres"` -> `"service_postgres"`
- Modify: `terraform/backups/main.tf:31` — `"Postgres"` -> `"service_postgres"`
- Modify: `terraform/pgadmin/main.tf:24` — `"Postgres"` -> `"service_postgres"`

**Step 1: Change the title field in each file**

In each file, change exactly one line: the `title = "Postgres"` inside the `data "onepassword_item"` block.

```hcl
  title = "service_postgres"
```

**Step 2: Commit**

```bash
git add terraform/postgres/main.tf terraform/backups/main.tf terraform/pgadmin/main.tf
git commit -m "refactor: rename Postgres secret to service_postgres in terraform"
```

---

### Task 5: Update terraform/litellm/main.tf

**Files:**
- Modify: `terraform/litellm/main.tf` — 9 title changes

**Step 1: Apply all title renames**

| Line | Current | New |
|------|---------|-----|
| 31 | `title = "litellm"` | `title = "service_litellm"` |
| 36 | `title = "postgres_litellm"` | `title = "db_litellm"` |
| 41 | `title = "OpenAI API Key"` | `title = "api_openai_key"` |
| 46 | `title = "Anthropic API Key"` | `title = "api_anthropic_key"` |
| 51 | `title = "Replicate API Key"` | `title = "api_replicate_key"` |
| 56 | `title = "Openrouter API Key"` | `title = "api_openrouter_key"` |
| 61 | `title = "Cohere API Key"` | `title = "api_cohere_key"` |
| 66 | `title = "Groq API Key"` | `title = "api_groq_key"` |
| 71 | `title = "Langfuse API Key"` | `title = "api_langfuse_key"` |

**Step 2: Commit**

```bash
git add terraform/litellm/main.tf
git commit -m "refactor: rename litellm secret titles to standard convention"
```

---

### Task 6: Update terraform/open-webui/main.tf

**Files:**
- Modify: `terraform/open-webui/main.tf:22` — `"litellm"` -> `"service_litellm"`

**Step 1: Change the title**

```hcl
  title = "service_litellm"
```

**Step 2: Commit**

```bash
git add terraform/open-webui/main.tf
git commit -m "refactor: rename litellm secret to service_litellm in open-webui"
```

---

### Task 7: Update terraform/n8n/main.tf

**Files:**
- Modify: `terraform/n8n/main.tf` — 2 title changes

**Step 1: Apply title renames**

| Line | Current | New |
|------|---------|-----|
| 22 | `title = "postgres_n8n"` | `title = "db_n8n"` |
| 27 | `title = "n8n_admin"` | `title = "service_n8n"` |

**Step 2: Commit**

```bash
git add terraform/n8n/main.tf
git commit -m "refactor: rename n8n secret titles to standard convention"
```

---

### Task 8: Update terraform/nautobot/main.tf

**Files:**
- Modify: `terraform/nautobot/main.tf` — 2 title changes

**Step 1: Apply title renames**

| Line | Current | New |
|------|---------|-----|
| 31 | `title = "Nautobot"` | `title = "service_nautobot"` |
| 36 | `title = "nautobot_db"` | `title = "db_nautobot"` |

**Step 2: Commit**

```bash
git add terraform/nautobot/main.tf
git commit -m "refactor: rename nautobot secret titles to standard convention"
```

---

### Task 9: Update terraform/langfuse/main.tf and terraform/restic/main.tf

**Files:**
- Modify: `terraform/langfuse/main.tf:31` — `"postgres_langfuse"` -> `"db_langfuse"`
- Modify: `terraform/restic/main.tf:33` — `"Restic"` -> `"backup_restic_password"`
- Modify: `terraform/restic/main.tf:38` — `"Backblaze"` -> `"api_backblaze_creds"`

**Step 1: Apply title renames**

langfuse/main.tf:
```hcl
  title = "db_langfuse"
```

restic/main.tf:
```hcl
  title = "backup_restic_password"
```
```hcl
  title = "api_backblaze_creds"
```

**Step 2: Commit**

```bash
git add terraform/langfuse/main.tf terraform/restic/main.tf
git commit -m "refactor: rename langfuse and restic secret titles to standard convention"
```

---

### Task 10: Copy secrets README into this repo

**Files:**
- Create: `docs/secrets/README.md` (copy from `~/git/octant-private/docs/secrets/README.md`)

**Step 1: Copy the file**

```bash
mkdir -p docs/secrets
cp ~/git/octant-private/docs/secrets/README.md docs/secrets/README.md
```

**Step 2: Commit**

```bash
git add docs/secrets/README.md
git commit -m "docs: add secrets naming convention reference"
```

---

### Task 11: Verify consistency across all sources of truth

**Step 1: Extract all unique 1Password titles from terraform**

```bash
grep -rh 'title = "' terraform/*/main.tf | grep -v '\[replace\]' | sed 's/.*title = "//;s/"//' | sort -u
```

Expected output (every title should be in `{category}_{name}` format):
```
api_anthropic_key
api_backblaze_creds
api_cohere_key
api_groq_key
api_langfuse_key
api_moonshot_key
api_openclaw_discord
api_openclaw_op_sa
api_openclaw_slack_app
api_openclaw_slack_bot
api_openai_key
api_openrouter_key
api_replicate_key
api_sendgrid_key
api_zai_key
backup_restic_password
db_langfuse
db_litellm
db_n8n
db_nautobot
db_phoenix
service_litellm
service_mariadb
service_nautobot
service_n8n
service_openclaw
service_postgres
```

**Step 2: Verify seed role covers all seeded items**

Every title used in terraform that is auto-generated should appear in `op_seed_items` in `roles/seed-onepassword/defaults/main.yml`. API keys and external service credentials should appear in `op_optional_items`.

**Step 3: Verify clear script covers all items**

Every title in the seed role's `op_seed_items` should appear in `SEEDED_ITEMS` in `scripts/clear-vault-secrets.sh`. Every title in `op_optional_items` should appear in `OPTIONAL_ITEMS`.

**Step 4: No legacy names remain**

```bash
grep -rn '"Postgres"\|"Restic"\|"Registry"\|"Backblaze"\|"Nautobot"\|"Cloudflare"\|"OpenAI API Key"\|"Anthropic API Key"\|"Replicate API Key"\|"Openrouter API Key"\|"Cohere API Key"\|"Groq API Key"\|"Langfuse API Key"\|"service_n8n"\|"n8n_admin"\|"nautobot_db"\|"postgres_litellm"\|"postgres_n8n"\|"postgres_langfuse"\|"postgres_phoenix"' roles/ scripts/ terraform/
```

Expected: **No output** (no legacy names remain anywhere).

**Step 5: Update progress tracker**

Add a note to `docs/plans/2026-02-21-vm-deployment-progress.md` documenting the secrets rename completion.
