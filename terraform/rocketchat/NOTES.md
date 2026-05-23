# Rocket.Chat Deployment Notes

## Access

- URL: `https://rocketchat.lab.shamsway.net/`
- Health check: `https://rocketchat.lab.shamsway.net/health`

## Initial Setup

On first visit, Rocket.Chat shows a setup wizard:

1. Create the admin account (use credentials from 1Password `service_rocketchat`)
2. Set organization info (optional)
3. Register or skip Rocket.Chat Cloud registration
4. Complete the wizard

## Architecture

- **Container**: `rocket.chat:latest` on a rootless Nomad agent
- **Database**: MongoDB 7 at `mongodb.service.consul:27017`, database `rocketchat`
- **Auth**: Uses MongoDB root credentials (from `service_mongodb` in 1Password)
- **Storage**: File uploads persist to `/mnt/services/rocketchat/uploads` (CephFS)
- **Ingress**: Traefik via Consul catalog, HTTPS with Cloudflare cert

## MongoDB Replica Set

Rocket.Chat requires MongoDB with a replica set. The existing MongoDB deployment
runs with `--replSet rs0`. The replica set member must be configured with
`mongodb.service.consul:27017` (not `localhost`) so that Rocket.Chat can reach it
from other nodes via Consul DNS.

To verify replica set config:
```bash
nomad alloc exec <mongodb-alloc-id> mongosh -u <user> -p <pass> --authenticationDatabase admin --eval "rs.conf()"
```

## Bot Accounts (OpenClaw Integration)

The OpenClaw gateway connects to RocketChat via bot accounts. After a DB reset,
these accounts must be recreated manually.

### Setup After DB Reset

1. Log in as `rcadmin` (credentials in 1Password `service_rocketchat`)
2. Create bot user `scotty-bot` (credentials in 1Password `bot_openclaw_rocketchat`):
   - Administration > Users > New
   - Username: `scotty-bot`, display name: `Scotty`
   - Set password from 1Password `bot_openclaw_rocketchat`
   - Role: `bot`
   - Require password change: **off**
   - Email verified: **on** (use a placeholder email)
3. Create `#bridge` as a **private group** (NOT public channel — the bundled
   `openclaw-rocketchat` plugin requires private groups for the `groups` config)
4. Invite `scotty-bot` to `#bridge`
5. Update credential files on CephFS:

```bash
# Get scotty-bot's new userId + authToken (use form encoding for passwords with !)
curl -s -X POST https://rocketchat.lab.shamsway.net/api/v1/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user=scotty-bot" \
  --data-urlencode "password=<from 1Password>" | jq '.data | {userId, authToken}'

# Update bots.json with the new userId + authToken
ssh octant-01 'cat > /mnt/services/openclaw-gateway/config/credentials/rocketchat/bots.json' <<'EOF'
{
  "scotty-bot": {
    "userId": "<new-userId>",
    "authToken": "<new-authToken>",
    "password": "<from 1Password>"
  }
}
EOF

# Update admin.json similarly
curl -s -X POST https://rocketchat.lab.shamsway.net/api/v1/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user=rcadmin" \
  --data-urlencode "password=<from 1Password>" | jq '.data | {userId, authToken}'

ssh octant-01 'cat > /mnt/services/openclaw-gateway/config/credentials/rocketchat/admin.json' <<'EOF'
{
  "userId": "<admin-userId>",
  "authToken": "<admin-authToken>",
  "username": "rcadmin",
  "password": "<from 1Password>"
}
EOF
```

6. Ensure `openclaw.json` has the `groups.bridge` section (required by bundled plugin):
   ```json
   "channels": {
     "rocketchat": {
       "groups": {
         "bridge": { "bots": ["scotty-bot"] }
       }
     }
   }
   ```
7. Restart the OpenClaw gateway to pick up new credentials

### Verification

```bash
# Check scotty-bot is connected
nomad alloc logs -job openclaw-gateway 2>&1 | grep scotty-bot
# Should show: 机器人 scotty-bot 已连接

# Check for errors (from inside container)
ALLOC=$(nomad job status openclaw-gateway | grep "run      running" | awk '{print $1}')
nomad alloc exec -task openclaw-gateway $ALLOC /bin/sh -c \
  'cat /tmp/openclaw/openclaw-*.log' | jq -r 'select(._meta.logLevelName == "ERROR") | .[1] // .[0]'

# Test scotty agent directly
nomad alloc exec -task openclaw-gateway $ALLOC /bin/sh -c \
  'node /app/openclaw.mjs agent --local --agent scotty --message "hello" --timeout 30'
```

## Secrets

| Secret | Location | Purpose |
|--------|----------|---------|
| `service_rocketchat` | 1Password (Octant vault) | Admin account (`rcadmin`) credentials |
| `bot_openclaw_rocketchat` | 1Password (Octant vault) | Bot account (`scotty-bot`) credentials |
| `service_mongodb` | 1Password (Octant vault) | MongoDB root credentials |
| `nomad/jobs/rocketchat` | Nomad variables | MongoDB user/pass injected at runtime |
| `nomad/jobs/openclaw-gateway` | Nomad variables | Bot user/pass + gateway token |

## Credential Files (CephFS)

After a DB reset, these files at `/mnt/services/openclaw-gateway/config/credentials/rocketchat/`
contain stale IDs and must be updated:

| File | Contents |
|------|----------|
| `bots.json` | Bot userId + password (must match new DB) |
| `admin.json` | Admin userId + authToken (must match new DB) |

## Operations

```bash
# Check status
nomad job status rocketchat

# View logs
nomad alloc logs -job rocketchat
nomad alloc logs -job rocketchat -stderr

# Restart
nomad job eval rocketchat

# Redeploy
cd terraform/rocketchat && terraform apply -auto-approve
```

## Resource Allocation

- CPU: 500 MHz
- Memory: 1024 MB
- Port: Dynamic (Traefik routes via Consul)
