# OpenClaw v2026.3.12 Upgrade Validation

Released: March 13, 2026

## Breaking Change: Cron/Doctor Migration

Cron jobs can no longer notify through ad hoc agent sends or fallback main-session summaries. Legacy cron storage requires migration via `openclaw doctor --fix`.

### Affected Agents

| Agent | Cron Usage | Delivery Target |
|-------|-----------|-----------------|
| Clawnerd | `cron` tool explicitly allowed | `#clawnerd` via RocketChat |
| Archivist | HEARTBEAT.md checks (6h ingestion, 30m health) | `#bridge` / `#knowledge` via RocketChat |

Current delivery routes directly to RocketChat channels (not via ad hoc agent sends), so behavioral impact may be minimal — but validation is required.

## Post-Upgrade Checklist

- [x] Update OpenClaw container image in `openclaw-gateway.nomad.hcl`
- [x] Deploy via `terraform apply` — running `192.168.122.1:5000/openclaw-gateway:2026.3.13`
- [x] Run `openclaw doctor --fix` to migrate cron storage
  - Migrated `dmPolicy` from top-level `channels.rocketchat` into `channels.rocketchat.accounts.default`
  - Added `wizard`, `meta` tracking sections
  - Found 2 orphan transcript files in scotty sessions (non-blocking)
  - Updated repo config (`config/openclaw.json`) to match migrated format
- [x] Clear agent model caches on CephFS — no caches present (clean state)
- [x] Verify `cron.sessionRetention: "6h"` is still honored — confirmed in live config
- [x] Verify workspace plugins aren't relying on auto-load — no plugin files found in any workspace
- [x] Check agent workspace hooks resolve correctly — no hooks files found in any workspace

## Cron Delivery Validation

- [ ] Trigger manual Archivist cron run — confirm ingestion scan results arrive in `#bridge`
- [ ] Trigger manual Archivist health check — confirm backend health results work
- [ ] Trigger manual Clawnerd cron run — confirm output arrives in `#clawnerd`

## New Features to Explore (No Config Changes Required)

### Control UI / Dashboard v2
Refreshed gateway dashboard with modular overview, chat, config, agent, and session views. Command palette, mobile bottom tabs, richer chat tools (slash commands, search, export, pinned messages). Available at `openclaw.lab.shamsway.net` after deploy.

### `sessions_yield` for Orchestrators
Archivist uses `sessions_spawn` to delegate to Vec/Graph/Notes-Ingest. New `sessions_yield` allows ending the current turn immediately with a hidden follow-up payload. Opt-in — could improve Archivist's delegation flow.

## Not Relevant

### vLLM / Provider Plugin Architecture
Ollama, vLLM, and SGLang moved to provider-plugin architecture. Does not affect this deployment — LiteLLM already abstracts backends behind an OpenAI-compatible API. No advantage to switching; would lose LiteLLM's load balancing, fallback routing, and unified API key management.

## Security Fixes (Applied Automatically with Image Update)

All server-side, no config changes needed. Feishu, LINE, Zalo webhook fixes don't apply (not configured).

Key fixes:
- Device pairing switched to short-lived bootstrap tokens
- Implicit workspace plugin auto-load disabled
- Unicode normalization in exec detection and approval prompts
- POSIX case sensitivity preserved in exec allowlists
- Session-scoped browser storage for Control UI auth tokens
- WebSocket pre-auth frame size limits
