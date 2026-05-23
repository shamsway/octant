#!/usr/bin/env bash
#
# openclaw-add-bot.sh — Automate adding a new OpenClaw bot to Rocketchat
#
# Automates: 1Password secret, Rocketchat user creation (with bot role),
#            API token retrieval, CephFS bots.json update, group creation/invite,
#            and openclaw.json config hints.
#
# Usage:
#   ./scripts/openclaw-add-bot.sh <agent-id> [display-name]
#
# Examples:
#   ./scripts/openclaw-add-bot.sh archivist "Archivist"
#   ./scripts/openclaw-add-bot.sh vec-ingest "Vec-Ingest"
#
# Prerequisites:
#   - op CLI authenticated (OP_SERVICE_ACCOUNT_TOKEN set)
#   - SSH access to octant-01
#   - jq installed
#   - Admin credentials at /mnt/services/openclaw-gateway/config/credentials/rocketchat/admin.json

set -euo pipefail

RC_URL="https://rocketchat.lab.shamsway.net"
CEPHFS_CREDS="/mnt/services/openclaw-gateway/config/credentials/rocketchat"
OP_VAULT="Octant"

# --- Args ---
AGENT_ID="${1:?Usage: $0 <agent-id> [display-name]}"
DISPLAY_NAME="${2:-$AGENT_ID}"
BOT_USERNAME="${AGENT_ID}-bot"
BOT_EMAIL="${BOT_USERNAME}@octant.local"
OP_ITEM="bot_${AGENT_ID}_rocketchat"

echo "=== OpenClaw Bot Setup: ${BOT_USERNAME} ==="
echo ""

# --- Validate tools ---
for cmd in op jq ssh curl; do
  command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

# --- Step 1: Create 1Password secret ---
echo "--- Step 1: 1Password secret ---"
if op item get "$OP_ITEM" --vault "$OP_VAULT" --format json &>/dev/null; then
  echo "1Password item '$OP_ITEM' already exists, reading password..."
  BOT_PASSWORD=$(op read "op://${OP_VAULT}/${OP_ITEM}/password")
else
  echo "Creating 1Password item '$OP_ITEM'..."
  op item create \
    --category login \
    --title "$OP_ITEM" \
    --vault "$OP_VAULT" \
    --generate-password=24,letters,digits,symbols \
    --url "$RC_URL" \
    "username=${BOT_USERNAME}" > /dev/null
  BOT_PASSWORD=$(op read "op://${OP_VAULT}/${OP_ITEM}/password")
  echo "Created with generated password."
fi
echo ""

# --- Step 2: Get admin credentials from CephFS ---
echo "--- Step 2: Loading admin credentials ---"
ADMIN_JSON=$(ssh octant-01 "cat ${CEPHFS_CREDS}/admin.json")
ADMIN_TOKEN=$(echo "$ADMIN_JSON" | jq -r '.authToken')
ADMIN_UID=$(echo "$ADMIN_JSON" | jq -r '.userId')

# Test admin auth
if ! curl -sf "${RC_URL}/api/v1/me" \
  -H "X-Auth-Token: ${ADMIN_TOKEN}" \
  -H "X-User-Id: ${ADMIN_UID}" > /dev/null 2>&1; then
  echo "ERROR: Admin credentials are stale. Re-login as rcadmin and update admin.json."
  exit 1
fi
echo "Admin credentials valid."
echo ""

# --- Step 3: Create Rocketchat user ---
echo "--- Step 3: Creating Rocketchat user '${BOT_USERNAME}' ---"
CREATE_RESULT=$(curl -s "${RC_URL}/api/v1/users.create" \
  -H "X-Auth-Token: ${ADMIN_TOKEN}" \
  -H "X-User-Id: ${ADMIN_UID}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg email "$BOT_EMAIL" \
    --arg name "$DISPLAY_NAME" \
    --arg password "$BOT_PASSWORD" \
    --arg username "$BOT_USERNAME" \
    '{email: $email, name: $name, password: $password, username: $username, roles: ["bot"], joinDefaultChannels: false, sendWelcomeEmail: false}'
  )")

if echo "$CREATE_RESULT" | jq -e '.success' > /dev/null 2>&1; then
  RC_BOT_ID=$(echo "$CREATE_RESULT" | jq -r '.user._id')
  echo "Created user: ${BOT_USERNAME} (ID: ${RC_BOT_ID})"
else
  ERROR=$(echo "$CREATE_RESULT" | jq -r '.error // "unknown error"')
  if echo "$ERROR" | grep -qi "already in use\|duplicate"; then
    echo "User '${BOT_USERNAME}' already exists, continuing..."
    RC_BOT_ID=$(curl -s "${RC_URL}/api/v1/users.info?username=${BOT_USERNAME}" \
      -H "X-Auth-Token: ${ADMIN_TOKEN}" \
      -H "X-User-Id: ${ADMIN_UID}" | jq -r '.user._id')
  else
    echo "ERROR creating user: ${ERROR}"
    exit 1
  fi
fi
echo ""

# --- Step 4: Login to get API token ---
echo "--- Step 4: Getting API token for '${BOT_USERNAME}' ---"
LOGIN_RESULT=$(curl -s -X POST "${RC_URL}/api/v1/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user=${BOT_USERNAME}" \
  --data-urlencode "password=${BOT_PASSWORD}")

if echo "$LOGIN_RESULT" | jq -e '.status == "success"' > /dev/null 2>&1; then
  BOT_USER_ID=$(echo "$LOGIN_RESULT" | jq -r '.data.userId')
  BOT_AUTH_TOKEN=$(echo "$LOGIN_RESULT" | jq -r '.data.authToken')
  echo "Got token: userId=${BOT_USER_ID}"
else
  echo "ERROR: Login failed. Check password."
  echo "$LOGIN_RESULT" | jq .
  exit 1
fi
echo ""

# --- Step 5: Update bots.json on CephFS ---
echo "--- Step 5: Updating bots.json on CephFS ---"
BOTS_JSON=$(ssh octant-01 "cat ${CEPHFS_CREDS}/bots.json")
UPDATED_BOTS=$(echo "$BOTS_JSON" | jq \
  --arg username "$BOT_USERNAME" \
  --arg userId "$BOT_USER_ID" \
  --arg authToken "$BOT_AUTH_TOKEN" \
  --arg password "$BOT_PASSWORD" \
  '. + {($username): {userId: $userId, authToken: $authToken, password: $password}}')

echo "$UPDATED_BOTS" | ssh octant-01 "cat > ${CEPHFS_CREDS}/bots.json"
echo "Updated bots.json with ${BOT_USERNAME}."
echo ""

# --- Step 6: Optionally create group and invite bot ---
echo "--- Step 6: Group setup (optional) ---"
read -rp "Create a new private group for this bot? [y/N] " CREATE_GROUP
if [[ "${CREATE_GROUP,,}" == "y" ]]; then
  read -rp "Group name: " GROUP_NAME
  GROUP_RESULT=$(curl -s "${RC_URL}/api/v1/groups.create" \
    -H "X-Auth-Token: ${ADMIN_TOKEN}" \
    -H "X-User-Id: ${ADMIN_UID}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg name "$GROUP_NAME" '{name: $name, members: []}')")
  if echo "$GROUP_RESULT" | jq -e '.success' > /dev/null 2>&1; then
    GROUP_ID=$(echo "$GROUP_RESULT" | jq -r '.group._id')
    echo "Created group: #${GROUP_NAME} (ID: ${GROUP_ID})"
  else
    echo "Group creation failed (may already exist): $(echo "$GROUP_RESULT" | jq -r '.error')"
    # Try to get existing group ID
    GROUP_ID=$(curl -s "${RC_URL}/api/v1/groups.info?roomName=${GROUP_NAME}" \
      -H "X-Auth-Token: ${ADMIN_TOKEN}" \
      -H "X-User-Id: ${ADMIN_UID}" | jq -r '.group._id // empty')
  fi

  if [ -n "${GROUP_ID:-}" ]; then
    echo "Inviting ${BOT_USERNAME} to #${GROUP_NAME}..."
    curl -s "${RC_URL}/api/v1/groups.invite" \
      -H "X-Auth-Token: ${ADMIN_TOKEN}" \
      -H "X-User-Id: ${ADMIN_UID}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg roomId "$GROUP_ID" --arg userId "$BOT_USER_ID" \
        '{roomId: $roomId, userId: $userId}')" | jq -r 'if .success then "Invited!" else "Invite failed: " + .error end'
  fi
fi
echo ""

# --- Step 7: Invite bot to existing groups ---
read -rp "Invite ${BOT_USERNAME} to existing group(s)? [y/N] " INVITE_EXISTING
if [[ "${INVITE_EXISTING,,}" == "y" ]]; then
  read -rp "Group name(s), comma-separated: " EXISTING_GROUPS
  IFS=',' read -ra GROUPS <<< "$EXISTING_GROUPS"
  for g in "${GROUPS[@]}"; do
    g=$(echo "$g" | xargs)  # trim whitespace
    GID=$(curl -s "${RC_URL}/api/v1/groups.info?roomName=${g}" \
      -H "X-Auth-Token: ${ADMIN_TOKEN}" \
      -H "X-User-Id: ${ADMIN_UID}" | jq -r '.group._id // empty')
    if [ -n "$GID" ]; then
      curl -s "${RC_URL}/api/v1/groups.invite" \
        -H "X-Auth-Token: ${ADMIN_TOKEN}" \
        -H "X-User-Id: ${ADMIN_UID}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg roomId "$GID" --arg userId "$BOT_USER_ID" \
          '{roomId: $roomId, userId: $userId}')" | jq -r "if .success then \"Invited to #${g}\" else \"Failed: \" + .error end"
    else
      echo "Group #${g} not found"
    fi
  done
fi
echo ""

# --- Summary ---
echo "==========================================="
echo "  Bot Setup Complete: ${BOT_USERNAME}"
echo "==========================================="
echo ""
echo "  1Password item:  ${OP_ITEM}"
echo "  RC username:     ${BOT_USERNAME}"
echo "  RC userId:       ${BOT_USER_ID}"
echo "  CephFS bots.json: updated"
echo ""
echo "  Next steps — add to openclaw.json:"
echo ""
echo "  Account (under channels.rocketchat.accounts):"
echo "    \"${AGENT_ID}\": {"
echo "      \"botUsername\": \"${BOT_USERNAME}\","
echo "      \"botDisplayName\": \"${DISPLAY_NAME}\""
echo "    }"
echo ""
echo "  Group (under channels.rocketchat.groups):"
if [ -n "${GROUP_NAME:-}" ]; then
echo "    \"${GROUP_NAME}\": {"
echo "      \"bots\": [\"${BOT_USERNAME}\"],"
echo "      \"requireMention\": false"
echo "    }"
else
echo "    \"<group-name>\": {"
echo "      \"bots\": [\"${BOT_USERNAME}\"],"
echo "      \"requireMention\": false"
echo "    }"
fi
echo ""
echo "  Binding (under bindings):"
if [ -n "${GROUP_NAME:-}" ]; then
echo "    {"
echo "      \"agentId\": \"${AGENT_ID}\","
echo "      \"match\": {"
echo "        \"channel\": \"rocketchat\","
echo "        \"accountId\": \"${AGENT_ID}\","
echo "        \"peer\": { \"kind\": \"channel\", \"id\": \"${GROUP_NAME}\" }"
echo "      }"
echo "    }"
else
echo "    {"
echo "      \"agentId\": \"${AGENT_ID}\","
echo "      \"match\": {"
echo "        \"channel\": \"rocketchat\","
echo "        \"accountId\": \"${AGENT_ID}\","
echo "        \"peer\": { \"kind\": \"channel\", \"id\": \"<group-name>\" }"
echo "      }"
echo "    }"
fi
echo ""
echo "  Then deploy config and restart:"
echo "    scp terraform/openclaw-gateway/config/openclaw.json octant-01:/mnt/services/openclaw-gateway/config/"
echo "    nomad job restart -on-error=fail -all-tasks openclaw-gateway"
echo ""
