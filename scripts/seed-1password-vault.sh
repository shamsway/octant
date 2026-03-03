#!/usr/bin/env bash
# Seed 1Password vault with items required by Terraform modules
#
# Reads secrets from .env and creates corresponding 1Password items
# that the Terraform onepassword_item data sources expect.
#
# Usage:
#   ./scripts/seed-1password-vault.sh                    # Create items in "Octant" vault
#   ./scripts/seed-1password-vault.sh --vault Dev        # Use a different vault
#   ./scripts/seed-1password-vault.sh --dry-run          # Show what would be created
#   ./scripts/seed-1password-vault.sh --force            # Overwrite existing items
#
# Prerequisites:
#   - op CLI installed and authenticated (op signin)
#   - .env file exists in project root (generate with ./scripts/generate-secrets.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/.env"
VAULT="Octant"
DRY_RUN=false
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vault)   VAULT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force)   FORCE=true; shift ;;
        --help|-h) echo "Usage: $0 [--vault NAME] [--dry-run] [--force]"; exit 0 ;;
        *)         echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Verify prerequisites
if ! command -v op &>/dev/null; then
    echo "ERROR: op CLI not found. Install from https://1password.com/downloads/command-line/"
    exit 1
fi

if ! op whoami &>/dev/null; then
    echo "ERROR: op CLI not authenticated. Run: op signin"
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env file not found at $ENV_FILE"
    echo "Generate one with: ./scripts/generate-secrets.sh"
    exit 1
fi

# Load .env values into associative array
declare -A ENV_VARS
while IFS= read -r line; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    # Strip surrounding quotes
    value="${value#\"}"
    value="${value%\"}"
    ENV_VARS["$key"]="$value"
done < "$ENV_FILE"

# Track results
CREATED=0
SKIPPED=0
ERRORS=0

# Create or update an item
# Usage: create_item "Title" "category" "field1=value1" "field2=value2" ...
create_item() {
    local title="$1"
    local category="$2"
    shift 2

    # Check if item already exists
    if op item get "$title" --vault "$VAULT" &>/dev/null; then
        if [[ "$FORCE" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "  [dry-run] Would overwrite: $title"
                SKIPPED=$((SKIPPED + 1))
                return
            fi
            echo "  Overwriting: $title"
            op item delete "$title" --vault "$VAULT" &>/dev/null
        else
            echo "  Exists (skip): $title"
            SKIPPED=$((SKIPPED + 1))
            return
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [dry-run] Would create: $title ($category) with fields: $*"
        CREATED=$((CREATED + 1))
        return
    fi

    # Build op item create command
    local cmd=(op item create --vault "$VAULT" --category "$category" --title "$title")
    for field in "$@"; do
        cmd+=("$field")
    done

    if "${cmd[@]}" &>/dev/null; then
        echo "  Created: $title"
        CREATED=$((CREATED + 1))
    else
        echo "  ERROR creating: $title"
        ERRORS=$((ERRORS + 1))
    fi
}

# Helper: get env var with fallback
env_val() {
    echo "${ENV_VARS[$1]:-}"
}

echo "=== Seeding 1Password vault: $VAULT ==="
echo ""

# Verify vault exists
if ! op vault get "$VAULT" &>/dev/null; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "NOTE: Vault '$VAULT' does not exist (would need to be created)"
    else
        echo "Creating vault: $VAULT"
        op vault create "$VAULT" || { echo "ERROR: Failed to create vault"; exit 1; }
    fi
fi

# --- Active modules (traefik, postgres, registry, litellm) ---

echo "Active modules:"

# Postgres (used by: postgres, backups, pgadmin)
# Terraform reads: .password
create_item "service_postgres" "login" \
    "password=${ENV_VARS[POSTGRES_PASSWORD]:-}"

# LiteLLM credentials (used by: litellm, open-webui)
# Terraform reads: .username, .password
create_item "service_litellm" "login" \
    "username=admin" \
    "password=$(env_val LITELLM_MASTER_KEY)"

# Postgres LiteLLM DB credentials (used by: litellm)
# Terraform reads: .username, .password
create_item "db_litellm" "login" \
    "username=litellm" \
    "password=$(env_val POSTGRES_PASSWORD)"

# Postgres n8n DB credentials (used by: n8n)
# Terraform reads: .username, .password
create_item "db_n8n" "login" \
    "username=n8n" \
    "password=$(env_val POSTGRES_PASSWORD)"

# Postgres Phoenix DB credentials (used by: phoenix)
# Terraform reads: .username, .password
create_item "db_phoenix" "login" \
    "username=phoenix" \
    "password=$(env_val POSTGRES_PASSWORD)"

# MariaDB root credentials (used by: mariadb)
# Terraform reads: .password
create_item "service_mariadb" "password" \
    "password=$(openssl rand -base64 32 | tr -d '=/+' | head -c 32)"

# API Keys - stored as logins with the key in the password field
# Terraform reads: .password for all of these

create_item "api_anthropic_key" "login" \
    "password=$(env_val ANTHROPIC_API_KEY)"

create_item "api_openai_key" "login" \
    "password=$(env_val OPENAI_API_KEY)"

# Optional API keys - create with placeholder if not set
create_item "api_replicate_key" "login" \
    "password=$(env_val REPLICATE_API_KEY)"

create_item "api_openrouter_key" "login" \
    "password=$(env_val OPENROUTER_API_KEY)"

create_item "api_cohere_key" "login" \
    "password=$(env_val COHERE_API_KEY)"

create_item "api_groq_key" "login" \
    "password=$(env_val GROQ_API_KEY)"

# Langfuse (used by: litellm)
# Terraform reads: .username (public key), .password (secret key)
create_item "api_langfuse_key" "login" \
    "username=$(env_val LANGFUSE_PUBLIC_KEY)" \
    "password=$(env_val LANGFUSE_SECRET_KEY)"

# Cloudflare (used by: traefik via .env passthrough)
# Not a 1Password item - passed via terraform_module_env_patterns
# But useful to store for reference
if [[ -n "$(env_val CLOUDFLARE_API_KEY)" ]]; then
    create_item "api_cloudflare_dns_token" "login" \
        "username=$(env_val CLOUDFLARE_USERNAME)" \
        "password=$(env_val CLOUDFLARE_API_KEY)"
fi

# Registry (used by: registry via .env passthrough)
create_item "service_registry" "login" \
    "username=admin" \
    "password=$(env_val REGISTRY_ADMIN_PASSWORD)"

echo ""
echo "--- Inactive modules (for future use) ---"

# Restic (used by: restic)
# Terraform reads: .password
create_item "backup_restic_password" "login" \
    "password=$(env_val RESTIC_PASSWORD)"

# Backblaze (used by: restic)
# Terraform reads: .username (access key ID)
if [[ -n "$(env_val B2_APPLICATION_KEY_ID)" ]]; then
    create_item "api_backblaze_creds" "login" \
        "username=$(env_val B2_APPLICATION_KEY_ID)" \
        "password=$(env_val B2_APPLICATION_KEY)"
fi

# Nautobot (used by: nautobot)
# Terraform reads: .username, .password, .section fields
if [[ -n "$(env_val NAUTOBOT_PASSWORD)" ]]; then
    create_item "service_nautobot" "login" \
        "username=admin" \
        "password=$(env_val NAUTOBOT_PASSWORD)"

    create_item "db_nautobot" "login" \
        "username=nautobot" \
        "password=$(env_val POSTGRES_PASSWORD)"
fi

# Langfuse DB (used by: langfuse)
create_item "db_langfuse" "login" \
    "username=langfuse" \
    "password=$(env_val POSTGRES_PASSWORD)"

echo ""
echo "=== Done ==="
echo "  Created: $CREATED"
echo "  Skipped: $SKIPPED"
echo "  Errors:  $ERRORS"
echo ""
echo "Verify with: op item list --vault '$VAULT'"
