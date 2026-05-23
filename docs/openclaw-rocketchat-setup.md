# OpenClaw + Rocket.Chat Setup Notes

Lessons learned from deploying OpenClaw gateway with Rocket.Chat integration on the octant cluster.

## Rocket.Chat Configuration

### Channel Config (not Plugin Config)

OpenClaw's Rocket.Chat integration is configured under `channels.rocketchat`, **not** `plugins.entries.rocketchat`. The plugin loads automatically via auto-detection when the channel config is present.

The `plugins.entries.rocketchat: plugin not found` warning is cosmetic and can be ignored, or removed from the plugins config to suppress it.

```json
{
  "channels": {
    "rocketchat": {
      "enabled": true,
      "serverUrl": "https://rocketchat.lab.shamsway.net",
      "dmPolicy": "pairing",
      "accounts": {
        "scotty": {
          "botUsername": "scotty-bot",
          "botDisplayName": "Scotty"
        }
      },
      "groups": {
        "bridge": {
          "bots": ["scotty-bot"]
        }
      }
    }
  }
}
```

### Bot User Setup

1. Create the bot user in Rocket.Chat admin (`Administration > Users`)
2. Set role to `bot`
3. Set a password — OpenClaw logs in with username/password, not tokens
4. The bot credentials are stored in 1Password as `bot_openclaw_rocketchat` (Login item with username + password)
5. Credentials are passed to the container via Nomad variables and set as env vars (`ROCKETCHAT_BOT_USER`, `ROCKETCHAT_BOT_PASSWORD`)

### Channel Setup

- Create a **private group** (not a public channel) named `bridge`
- Add the bot user to the group
- In `openclaw.json`, the `groups.bridge.bots` array lists which bot accounts participate in that group
- The binding config maps the agent to the channel:

```json
{
  "bindings": [
    {
      "agentId": "scotty",
      "match": {
        "channel": "rocketchat",
        "accountId": "scotty",
        "peer": {
          "kind": "channel",
          "id": "bridge"
        }
      }
    }
  ]
}
```

### Credentials on CephFS

On first successful connection, OpenClaw writes bot credentials to:
```
/mnt/services/openclaw-gateway/config/credentials/rocketchat/
├── admin.json    # Admin/pairing credentials
└── bots.json     # Bot auth tokens
```

These are auto-managed. If the bot password changes in Rocket.Chat, delete these files and restart the allocation so OpenClaw re-authenticates.

## Model Provider: Use LiteLLM, Not Direct vLLM

OpenClaw's `openai-completions` API type constructs request URLs as `${baseUrl}/chat/completions`. Despite the config having `baseUrl: "http://192.168.122.1:8000/v1"`, the actual HTTP requests hit `/chat/completions` without the `/v1` prefix, causing vLLM to return 404.

The root cause is somewhere in OpenClaw's internal HTTP client or URL resolution — the `/v1` path component gets stripped before the request is sent.

**Fix:** Route through LiteLLM, which handles URL construction correctly:

```json
{
  "models": {
    "providers": {
      "litellm": {
        "baseUrl": "http://litellm.service.consul:4000/v1",
        "apiKey": "<litellm-master-key>",
        "api": "openai-completions",
        "models": [
          {
            "id": "local/glm-5-fp8",
            "name": "GLM-5 FP8",
            "contextWindow": 128000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "litellm/local/glm-5-fp8"
      }
    }
  }
}
```

The model ID in OpenClaw (`local/glm-5-fp8`) must match the `model_name` in LiteLLM's `config.yaml`.

## Debugging Checklist

1. **Check gateway logs for model line:**
   ```
   agent model: litellm/local/glm-5-fp8
   ```
   If it says `vllm/glm-5-fp8`, the old config is still loaded.

2. **Test LiteLLM independently:**
   ```bash
   curl -X POST http://litellm.service.consul:4000/v1/chat/completions \
     -H "Authorization: Bearer <key>" -H "Content-Type: application/json" \
     -d '{"model":"local/glm-5-fp8","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'
   ```

3. **Test from inside the allocation:**
   ```bash
   nomad alloc exec -task openclaw-gateway <alloc> \
     node /app/openclaw.mjs agent --local --agent scotty --message "say hi" --json --timeout 30
   ```

4. **Check vLLM logs for request paths:**
   ```bash
   docker logs --tail 20 vllm-glm5 2>&1 | grep POST
   ```
   Should see `POST /v1/chat/completions 200`. If you see `POST /chat/completions 404`, the request is bypassing LiteLLM.

5. **Verify Consul DNS works from the container:**
   ```bash
   nomad alloc exec -task openclaw-gateway <alloc> \
     curl -s http://litellm.service.consul:4000/health/liveliness
   ```

## Config Deployment

The `openclaw.json` is **not** managed by Terraform. It lives on CephFS and is volume-mounted. To deploy changes:

```bash
# Edit locally
vi terraform/openclaw-gateway/config/openclaw.json

# Push to CephFS
cat terraform/openclaw-gateway/config/openclaw.json | \
  ssh admin@192.168.122.101 "sudo -u hashi tee /mnt/services/openclaw-gateway/config/openclaw.json > /dev/null"

# Restart
ssh admin@192.168.122.101 'sudo -u hashi nomad alloc restart <alloc-id>'
```
