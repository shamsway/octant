#!/usr/bin/env bash
#
# Clear auto-generated secrets from the 1Password Octant vault.
# Only removes items created by the seed-onepassword role.
# Does NOT touch manually-created items (API keys, external credentials).
#
# Usage:
#   ./scripts/clear-vault-secrets.sh              # interactive confirmation
#   ./scripts/clear-vault-secrets.sh --force       # skip confirmation
#   ./scripts/clear-vault-secrets.sh --all         # also remove optional/manual items
#   ./scripts/clear-vault-secrets.sh --dry-run     # show what would be deleted

set -euo pipefail

VAULT_NAME="${OP_VAULT_NAME:-Octant}"

# Items created by seed-onepassword role
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

# Items created manually for optional services
OPTIONAL_ITEMS=(
  "api_openai_key"
  "api_anthropic_key"
  "api_replicate_key"
  "api_openrouter_key"
  "api_cohere_key"
  "api_groq_key"
  "api_langfuse_key"
  "service_n8n"
  "api_sendgrid_key"
)

FORCE=false
DRY_RUN=false
INCLUDE_ALL=false

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --dry-run) DRY_RUN=true ;;
    --all) INCLUDE_ALL=true ;;
    --help|-h)
      echo "Usage: $0 [--force] [--dry-run] [--all]"
      echo ""
      echo "  --force     Skip confirmation prompt"
      echo "  --dry-run   Show what would be deleted without deleting"
      echo "  --all       Also delete optional/manually-created items"
      echo ""
      echo "Deletes auto-generated 1Password items from the '${VAULT_NAME}' vault."
      echo "Use before 'make rebuild' to test clean secret generation."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

# Check op CLI is authenticated
if ! op vault get "$VAULT_NAME" --format json > /dev/null 2>&1; then
  echo "Error: Cannot access 1Password vault '${VAULT_NAME}'."
  echo "Ensure OP_SERVICE_ACCOUNT_TOKEN is set (source .envrc or export it)."
  exit 1
fi

# Build the list of items to delete
ITEMS_TO_DELETE=("${SEEDED_ITEMS[@]}")
if [ "$INCLUDE_ALL" = true ]; then
  ITEMS_TO_DELETE+=("${OPTIONAL_ITEMS[@]}")
fi

# Check which items exist
EXISTING_ITEMS=$(op item list --vault "$VAULT_NAME" --format json | python3 -c "
import sys, json
items = json.load(sys.stdin)
for item in items:
    print(item['title'])
" 2>/dev/null)

FOUND_ITEMS=()
for title in "${ITEMS_TO_DELETE[@]}"; do
  if echo "$EXISTING_ITEMS" | grep -qxF "$title"; then
    FOUND_ITEMS+=("$title")
  fi
done

if [ ${#FOUND_ITEMS[@]} -eq 0 ]; then
  echo "No matching items found in vault '${VAULT_NAME}'. Nothing to delete."
  exit 0
fi

echo "Items to delete from vault '${VAULT_NAME}':"
for title in "${FOUND_ITEMS[@]}"; do
  if [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] $title"
  else
    echo "  - $title"
  fi
done

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "Dry run complete. No items were deleted."
  exit 0
fi

if [ "$FORCE" != true ]; then
  echo ""
  read -rp "Delete ${#FOUND_ITEMS[@]} items? (y/N) " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

echo ""
for title in "${FOUND_ITEMS[@]}"; do
  if op item delete "$title" --vault "$VAULT_NAME" 2>/dev/null; then
    echo "Deleted: $title"
  else
    echo "Failed to delete: $title"
  fi
done

echo ""
echo "Done. Run 'make seed-secrets' to regenerate credentials."
