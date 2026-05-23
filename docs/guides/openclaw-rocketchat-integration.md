# OpenClaw Rocketchat Integration Guide

Connecting OpenClaw agents to Rocketchat on the Octant homelab. Covers bot account creation, credential management, config schema, DM and group setup, and multi-agent patterns.

**Related docs:**
- `docs/guides/openclaw-agent-deployment.md` — full agent team deployment lifecycle
- `terraform/rocketchat/NOTES.md` — Rocketchat deployment, DB reset recovery, secrets inventory
- `terraform/openclaw-gateway/README.md` — single-agent (Scotty) deployment

---

## Plugin Identification

The bundled plugin is `openclaw-rocketchat` (Kxiandaoyan/openclaw-rocketchat), **not** the
`@cloudrise/openclaw-channel-rocketchat` npm package. These are entirely different plugins with
different config schemas:

| Field | Bundled plugin (`openclaw-rocketchat`) | Cloudrise plugin |
|-------|----------------------------------------|------------------|
| Server URL key | `serverUrl` | `baseUrl` |
| Credentials | Separate files on CephFS | Inline `userId` / `authToken` |
| Group type | Private groups only (type `p`) | Public channels |
| Plugin entry name | `openclaw-rocketchat` | `rocketchat` |

**Always use the bundled plugin's schema.** The plugin source is at
`/app/extensions/openclaw-rocketchat/` inside the container.

---

## Config Schema

From `openclaw.plugin.json` (v0.3.1):

```json
{
  "serverUrl": "https://rocketchat.lab.shamsway.net",
  "dmPolicy": "pairing",
  "accounts": {
    "<account-id>": {
      "botUsername": "<rocketchat-bot-username>",
      "botDisplayName": "<display-name>"
    }
  },
  "groups": {
    "<group-name>": {
      "requireMention": false,
      "bots": ["<bot-username>"]
    }
  }
}
```

This goes under `channels.rocketchat` in `openclaw.json`. The full structure:

```json
{
  "channels": {
    "rocketchat": {
      "enabled": true,
      "serverUrl": "https://rocketchat.lab.shamsway.net",
      "dmPolicy": "pairing",
      "accounts": { ... },
      "groups": { ... }
    }
  }
}
```

The plugin must also be enabled under `plugins.entries`:

```json
{
  "plugins": {
    "entries": {
      "openclaw-rocketchat": { "enabled": true }
    }
  }
}
```

**Note:** Use `"openclaw-rocketchat"`, not `"rocketchat"`. Using the wrong name produces
`"plugin not found: rocketchat"` at startup.

---

## Adding a New Bot Account

### Automated Setup

Use the `openclaw-add-bot.sh` script to automate the entire flow:

```bash
./scripts/openclaw-add-bot.sh <agent-id> [display-name]
# Example: ./scripts/openclaw-add-bot.sh archivist "Archivist"
```

The script handles: 1Password secret creation, Rocketchat user creation (with bot role),
API token retrieval, CephFS `bots.json` update, and optional group creation/invite.
It prints the exact JSON snippets to add to `openclaw.json` at the end.

Prerequisites: `op` CLI authenticated, SSH access to octant-01, `jq` installed.

### Manual Setup

#### 1. Create the Rocketchat User

Log in as `rcadmin` (credentials in 1Password `service_rocketchat`).

Administration > Users > New:

| Field | Value |
|-------|-------|
| Username | `<agent-id>-bot` (e.g., `archivist-bot`) |
| Display Name | Agent's display name (e.g., `Archivist`) |
| Password | From 1Password (create entry `bot_openclaw_rocketchat` or add to existing) |
| Role | `bot` |
| Require password change | **off** |
| Email verified | **on** (use placeholder like `<agent-id>-bot@octant.local`) |

### 2. Get API Credentials

Use form-encoded login — **JSON body silently fails with 401 for passwords containing `!`**:

```bash
curl -s -X POST https://rocketchat.lab.shamsway.net/api/v1/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user=<agent-id>-bot" \
  --data-urlencode "password=<from 1Password>" | jq '.data | {userId, authToken}'
```

### 3. Update Credential Files on CephFS

Bot credentials live at `/mnt/services/openclaw-gateway/config/credentials/rocketchat/bots.json`.
All bots share a single file:

```bash
ssh octant-01 'cat /mnt/services/openclaw-gateway/config/credentials/rocketchat/bots.json'
```

Add the new bot entry:

```json
{
  "scotty-bot": {
    "userId": "...",
    "authToken": "...",
    "password": "..."
  },
  "archivist-bot": {
    "userId": "<new-userId>",
    "authToken": "<new-authToken>",
    "password": "<from 1Password>"
  }
}
```

The plugin uses credentials from this file — they are **not** inline in `openclaw.json`.

Admin credentials are separate at `admin.json` in the same directory:

```json
{
  "userId": "<admin-userId>",
  "authToken": "<admin-authToken>",
  "username": "rcadmin",
  "password": "<from 1Password>"
}
```

### 4. Add Account to openclaw.json

Under `channels.rocketchat.accounts`, add an entry keyed by account ID:

```json
"accounts": {
  "scotty": {
    "botUsername": "scotty-bot",
    "botDisplayName": "Scotty"
  },
  "archivist": {
    "botUsername": "archivist-bot",
    "botDisplayName": "Archivist"
  }
}
```

The account key (e.g., `"archivist"`) is the `accountId` referenced in bindings.

---

## Room Types

### Private Groups (Proven Pattern)

The plugin's `groups` config maps to Rocketchat **private groups** (type `p`). This is the
working, tested pattern.

**Setup:**

1. Create a **private group** in Rocketchat (NOT a public channel)
2. Invite the bot user(s) to the group
3. Add a `groups` entry in `openclaw.json`:

```json
"groups": {
  "bridge": {
    "bots": ["scotty-bot"]
  },
  "research": {
    "bots": ["archivist-bot", "scotty-bot"],
    "requireMention": true
  }
}
```

**Key fields:**

| Field | Default | Purpose |
|-------|---------|---------|
| `bots` | (required) | Array of bot usernames that should join this group |
| `requireMention` | `false` | When `true`, bot only responds when `@mentioned`. Recommended for multi-user groups. |

**Without the `groups` entry**, the plugin has no room to subscribe to and logs:
`群组「<name>」不存在！请运行: openclaw rocketchat add-group`

### Public Channels (Not Supported)

The bundled plugin does **not** support public channels (type `c`) via the `groups` config.
The group subscription logic looks for private groups only. If you need a bot in what would
be a public channel, create it as a private group instead.

### Direct Messages (DMs)

DMs are controlled by the `dmPolicy` setting at the channel level:

| Policy | Behavior |
|--------|----------|
| `pairing` | Each bot auto-creates a DM with users who message it. **Default and recommended.** |
| `allowlist` | Only pre-approved users can DM bots |
| `open` | Anyone on the Rocketchat instance can DM any bot |

**No `groups` config is needed for DMs** — they work through accounts + bindings + `dmPolicy`.

---

## Bindings

Bindings route incoming messages to agents. Each binding says: "when a message arrives matching
this pattern, hand it to this agent."

### Group Binding

```json
{
  "agentId": "archivist",
  "match": {
    "channel": "rocketchat",
    "accountId": "archivist",
    "peer": {
      "kind": "channel",
      "id": "research"
    }
  }
}
```

- `agentId` — must match an agent in `agents.list`
- `accountId` — must match a key in `channels.rocketchat.accounts`
- `peer.id` — must match a key in `channels.rocketchat.groups` (and the Rocketchat group name)

### DM Binding

```json
{
  "agentId": "scotty",
  "match": {
    "channel": "rocketchat",
    "accountId": "scotty",
    "peer": {
      "kind": "dm"
    }
  }
}
```

Using `"peer": { "kind": "dm" }` (without an `id`) catches all DMs to that account's bot.

### Multiple Bindings Per Agent

An agent can have multiple bindings — e.g., one for a group and one for DMs:

```json
"bindings": [
  {
    "agentId": "scotty",
    "match": { "channel": "rocketchat", "accountId": "scotty", "peer": { "kind": "channel", "id": "bridge" } }
  },
  {
    "agentId": "scotty",
    "match": { "channel": "rocketchat", "accountId": "scotty", "peer": { "kind": "dm" } }
  }
]
```

### Multi-Bot Groups

Multiple bots can join the same group. List all bot usernames in the group's `bots` array,
and create a binding for each agent:

```json
"groups": {
  "research": {
    "bots": ["archivist-bot", "scotty-bot"],
    "requireMention": true
  }
}
```

```json
"bindings": [
  {
    "agentId": "archivist",
    "match": { "channel": "rocketchat", "accountId": "archivist", "peer": { "kind": "channel", "id": "research" } }
  },
  {
    "agentId": "scotty",
    "match": { "channel": "rocketchat", "accountId": "scotty", "peer": { "kind": "channel", "id": "research" } }
  }
]
```

Set `requireMention: true` in multi-bot groups so bots don't all respond to every message.

---

## Complete Example: Adding an "Archivist" Agent to Rocketchat

This assumes the agent is already defined in `agents.list` and has a workspace. See
`docs/guides/openclaw-agent-deployment.md` for the full agent setup workflow.

### 1. Rocketchat Setup

- Create user `archivist-bot` (role: `bot`) in Rocketchat admin
- Create private group `#research`
- Invite `archivist-bot` to `#research`

### 2. Get Credentials

```bash
curl -s -X POST https://rocketchat.lab.shamsway.net/api/v1/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user=archivist-bot" \
  --data-urlencode "password=<from 1Password>" | jq '.data | {userId, authToken}'
```

### 3. Update CephFS Credential File

Add to `/mnt/services/openclaw-gateway/config/credentials/rocketchat/bots.json`:

```json
{
  "scotty-bot": { "userId": "...", "authToken": "...", "password": "..." },
  "archivist-bot": { "userId": "<new>", "authToken": "<new>", "password": "<from 1Password>" }
}
```

### 4. Update openclaw.json

Add account:
```json
"channels": {
  "rocketchat": {
    "accounts": {
      "archivist": { "botUsername": "archivist-bot", "botDisplayName": "Archivist" }
    },
    "groups": {
      "research": { "bots": ["archivist-bot"], "requireMention": true }
    }
  }
}
```

Add bindings:
```json
"bindings": [
  { "agentId": "archivist", "match": { "channel": "rocketchat", "accountId": "archivist", "peer": { "kind": "channel", "id": "research" } } },
  { "agentId": "archivist", "match": { "channel": "rocketchat", "accountId": "archivist", "peer": { "kind": "dm" } } }
]
```

### 5. Restart Gateway

Channel changes require a full restart:

```bash
./botctl gateway restart
# or
ALLOC=$(nomad job status openclaw-gateway | grep "run      running" | awk '{print $1}')
nomad alloc restart $ALLOC
```

### 6. Verify

```bash
# Check bot connection (wait ~20s after restart for health check)
nomad alloc logs -job openclaw-gateway 2>&1 | grep archivist-bot
# Look for: 机器人 archivist-bot 已连接

# Check room subscription
nomad alloc logs -job openclaw-gateway 2>&1 | grep "已订阅房间"
# Look for: archivist-bot: 已订阅房间 <room-id>

# Test agent directly
ALLOC=$(nomad job status openclaw-gateway | grep "run      running" | awk '{print $1}')
nomad alloc exec -task openclaw-gateway $ALLOC \
  node /app/openclaw.mjs agent --local --agent archivist --message "hello" --timeout 30
```

---

## Credential Files (CephFS)

All credential files live at `/mnt/services/openclaw-gateway/config/credentials/rocketchat/`:

| File | Contents | When to Update |
|------|----------|----------------|
| `bots.json` | All bot userId + authToken + password | After DB reset or new bot |
| `admin.json` | Admin userId + authToken + password | After DB reset |

After a Rocketchat DB reset, **all credentials become stale** and must be regenerated.
See `terraform/rocketchat/NOTES.md` for the full DB reset recovery procedure.

---

## Secrets Inventory

| Secret | Location | Purpose |
|--------|----------|---------|
| `service_rocketchat` | 1Password (Octant vault) | Admin account (`rcadmin`) credentials |
| `bot_openclaw_rocketchat` | 1Password (Octant vault) | Bot account (`scotty-bot`) credentials |
| `nomad/jobs/openclaw-gateway` | Nomad variables | `ROCKETCHAT_BOT_USER` / `ROCKETCHAT_BOT_PASSWORD` injected at runtime |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "群组「X」不存在！请运行: openclaw rocketchat add-group" | Missing `groups` entry in config, or room is a public channel not a private group | Add `groups.<name>` entry; convert room to private group |
| "机器人 undefined 无凭据，跳过" | Phantom `accounts.default` created by `openclaw doctor --fix` | Remove `accounts.default`; keep only named accounts |
| "未配置 serverUrl，无法启动" | Using `baseUrl` (cloudrise schema) instead of `serverUrl` | Use `serverUrl` — this is the bundled plugin |
| Plugin shows "Configured: No" in admin UI | Missing `groups` section, or wrong plugin name in `plugins.entries` | Use `openclaw-rocketchat` (not `rocketchat`); ensure `groups` section exists |
| Bot connected but not responding in group | Missing binding, or binding `peer.id` doesn't match group name | Add/fix binding with correct `accountId` and `peer.id` |
| Bot connected but not responding to DMs | Missing DM binding or wrong `dmPolicy` | Add binding with `"peer": { "kind": "dm" }` |
| 401 on login API call | Password contains `!` and request used JSON body | Use `Content-Type: application/x-www-form-urlencoded` with `--data-urlencode` |
| "plugin not found: rocketchat" | Wrong plugin entry name | Use `"openclaw-rocketchat"` in `plugins.entries` |
| Channel changes not taking effect | Hot-reload doesn't cover channels/plugins | Full allocation restart required |
| Stale credentials after DB reset | Bot userId/authToken from old DB | Re-login via API, update `bots.json` and `admin.json` on CephFS |

### openclaw doctor --fix Warning

`openclaw doctor` runs automatically on startup and may propose config migrations. Using
`--fix` can break the bundled plugin by:

- Moving `dmPolicy` into `channels.rocketchat.accounts.default`
- Creating a phantom `"default"` account entry with no `botUsername`
- The gateway then logs "机器人 undefined 无凭据，跳过" and skips the phantom account

**Fix:** Remove `accounts.default` and ensure `dmPolicy` stays at the `channels.rocketchat` level.

---

## Checklist: New Bot Integration

```
Rocketchat:
- [ ] Bot user created (role: bot, password change off, email verified on)
- [ ] Bot credentials stored in 1Password
- [ ] Private group created (if needed) — NOT a public channel
- [ ] Bot invited to group

Credentials:
- [ ] Login API called with form encoding (not JSON)
- [ ] userId + authToken obtained
- [ ] bots.json updated on CephFS

Config (openclaw.json):
- [ ] Account added under channels.rocketchat.accounts
- [ ] Group added under channels.rocketchat.groups (if using groups)
- [ ] Binding(s) added for group and/or DM
- [ ] openclaw-rocketchat plugin enabled in plugins.entries

Deploy:
- [ ] Config deployed to CephFS (or updated in repo + botctl config deploy)
- [ ] Gateway restarted (channel changes require restart)
- [ ] Wait ~20s for health check

Verify:
- [ ] Bot shows "已连接" in logs
- [ ] Bot shows "已订阅房间" for each group
- [ ] Bot responds to messages in group
- [ ] Bot responds to DMs (if DM binding added)
```
