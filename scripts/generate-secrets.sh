#!/usr/bin/env bash
# Generate secrets for Octant VM deployment
# Creates .env file with random passwords for services that need them
#
# Usage:
#   ./scripts/generate-secrets.sh
#   # Then populate TAILSCALE_CLOUD_KEY manually
#
# Secrets that must be provided manually:
#   - TAILSCALE_CLOUD_KEY: From Tailscale admin console (auth key)
#   - ANTHROPIC_API_KEY: Only if deploying LiteLLM with Anthropic
#   - OPENAI_API_KEY: Only if deploying LiteLLM with OpenAI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/.env"

# Generate a random password of specified length
gen_password() {
    local length="${1:-24}"
    openssl rand -base64 "$length" | tr -d '=/+' | head -c "$length"
}

# Generate a Consul/Nomad gossip key (base64-encoded 32 bytes)
gen_gossip_key() {
    openssl rand -base64 32
}

if [[ -f "$ENV_FILE" ]]; then
    echo "WARNING: $ENV_FILE already exists."
    read -p "Overwrite? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "Generating secrets for Octant deployment..."

cat > "$ENV_FILE" << EOF
# Octant Deployment Secrets
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
#
# NOTE: Add your own values for items marked CHANGE_ME

# --- Cluster Secrets (auto-generated) ---
CONSUL_GOSSIP_KEY=$(gen_gossip_key)
NOMAD_GOSSIP_KEY=$(gen_gossip_key)

# --- Tailscale (REQUIRED - get from https://login.tailscale.com/admin/settings/keys) ---
TAILSCALE_CLOUD_KEY=CHANGE_ME

# --- Service Passwords (auto-generated) ---
POSTGRES_PASSWORD=$(gen_password 24)
REGISTRY_ADMIN_PASSWORD=$(gen_password 16)
LITELLM_MASTER_KEY=sk-$(gen_password 32)

# --- Backup (auto-generated) ---
RESTIC_PASSWORD=$(gen_password 32)

# --- LLM API Keys (optional - only needed if deploying LiteLLM) ---
ANTHROPIC_API_KEY=
OPENAI_API_KEY=

# --- Docker Hub (optional - avoids rate limits) ---
DOCKER_HUB_USERNAME=
DOCKER_HUB_PASSWORD=
EOF

chmod 600 "$ENV_FILE"

echo ""
echo "=== Secrets generated: $ENV_FILE ==="
echo ""
echo "Auto-generated (ready to use):"
echo "  - CONSUL_GOSSIP_KEY"
echo "  - NOMAD_GOSSIP_KEY"
echo "  - POSTGRES_PASSWORD"
echo "  - REGISTRY_ADMIN_PASSWORD"
echo "  - LITELLM_MASTER_KEY"
echo "  - RESTIC_PASSWORD"
echo ""
echo "Manual action required:"
echo "  - TAILSCALE_CLOUD_KEY: Get from https://login.tailscale.com/admin/settings/keys"
echo "    (Set to empty string or remove tailscale role from octant.yml to skip)"
echo "  - ANTHROPIC_API_KEY: Optional, for LiteLLM"
echo ""
echo "File permissions set to 600 (owner read/write only)."
