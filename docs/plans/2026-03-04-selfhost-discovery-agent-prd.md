# PRD: Self-Hosted App Discovery Agent

**Date:** 2026-03-04
**Status:** Draft
**Type:** OpenClaw Agent + Skill

## Problem

The octant lab's autodeploy skill validation requires a steady pipeline of candidate self-hosted applications. Currently, candidate discovery is manual — reading newsletters, browsing directories, and relying on word-of-mouth. The autodeploy candidates design doc (`docs/plans/2026-02-27-autodeploy-candidates-design.md`) has 10 of 17 candidates deployed, and the remaining 7 are well-defined. What's missing is a systematic way to discover *new* candidates as they emerge.

[selfh.st](https://selfh.st/) is the leading directory and newsletter for self-hosted applications, covering 1,000+ apps with categories, GitHub star counts, license info, and weekly digest emails. However, it has **no public API for its app directory** — the data is rendered client-side from a private database backed by Ghost CMS.

## Goals

1. **Automated discovery**: Surface new self-hosted apps relevant to the lab's needs without manual browsing
2. **Structured assessment**: Evaluate candidates against autodeploy difficulty criteria (dependencies, volumes, config complexity)
3. **Lab relevance filtering**: Prioritize apps that complement existing infrastructure (Postgres, Redis, CephFS, Traefik, LiteLLM, Rocket.Chat)
4. **Newsletter intelligence**: Extract structured insights from the weekly Self-Host Weekly newsletter
5. **On-demand search**: Allow crew members to ask "find me a self-hosted X alternative" and get actionable results

## Non-Goals

- Fully automating the autodeploy process end-to-end (discovery only, not deployment)
- Replacing the human-curated candidates doc (agent produces recommendations, human decides)
- Scraping or mirroring the selfh.st database (respect the site's data boundaries)
- Building a general-purpose web scraper (focused on selfh.st + GitHub)

## Architecture

```
                   selfh.st Newsletter (weekly email)
                              |
                              v
                   n8n (email trigger / webhook)
                              |
                              v
                   Rocket.Chat (#app-discovery channel)
                              |
                              v
                   OpenClaw Gateway (Scotty or dedicated agent)
                              |
                   +-----------+-----------+
                   |                       |
            Newsletter Parser        On-Demand Search
                   |                       |
                   v                       v
            Ghost Content API       Browser tool (selfh.st/apps)
            (structured posts)      (search + filter directory)
                   |                       |
                   +-----------+-----------+
                              |
                              v
                   GitHub API (via web_fetch)
                   - Compose files
                   - Dependencies
                   - Star count / activity
                   - License
                              |
                              v
                   Candidate Assessment
                   - Autodeploy difficulty rating
                   - Lab relevance score
                   - Dependency analysis
                   - Recommended deployment order
                              |
                              v
                   Rocket.Chat report (#app-discovery)
```

## Data Sources

### selfh.st — Available Programmatic Access

| Source | URL | Data | Reliability |
|--------|-----|------|-------------|
| Ghost Content API | `https://selfh.st/ghost/api/content/posts/?key=a4717b8b11f6e5ae98a6b78e16` | Newsletter posts (HTML/plaintext), pagination, tag filtering | High — embedded public key, standard Ghost API |
| RSS Feed | `https://selfh.st/rss/` | Newsletter entries (truncated) | High — standard RSS 2.0 |
| Icons index.json | `https://cdn.jsdelivr.net/gh/selfhst/icons@main/index.json` | App names, slugs, categories, icon availability | High — GitHub-backed, CDN-cached |
| Per-app release RSS | Linked from app tiles in directory | Individual app stable release feeds | Medium — URLs not programmatically discoverable |
| App directory (browser) | `https://selfh.st/apps/` | Full app metadata (description, stars, license, language, tags) | Requires browser automation |

### GitHub — Per-App Deep Dive

For each candidate surfaced, fetch from GitHub:
- `docker-compose.yml` / `docker-compose.yaml` — dependencies, ports, volumes
- README.md — setup instructions, environment variables
- Repository metadata — stars, last commit, license, language

### Lab Context — Existing Infrastructure

The agent needs awareness of:
- **Deployed apps**: IT-Tools, Linkding, Fusion, Docmost, Linkwarden, Gitea, Rocket.Chat, NATS, FalkorDB, n8n, SearXNG, Excalidraw, etc.
- **Shared services**: PostgreSQL, MariaDB, Redis, Qdrant, CephFS, Traefik, LiteLLM, MinIO
- **Deployment patterns validated**: Zero-config (IT-Tools), SQLite volumes (Linkding, Fusion), Postgres+Redis (Docmost), Postgres-only (Linkwarden, Gitea), MongoDB (Rocket.Chat)
- **Remaining gaps**: SSO/OIDC (Authentik), full-text search (Meilisearch), message broker (RabbitMQ), identity provider, CI/CD

## Agent Design

### Option A: Dedicated Agent (Recommended)

Add a new agent to the OpenClaw gateway roster:

| Role | Name | Emoji | Persona |
|------|------|-------|---------|
| Discovery / Quartermaster | Uhura | `📡` | Communications officer of the USS Octant. Monitors all frequencies (newsletters, feeds, directories) for new technology. Reports discoveries with precise technical assessments. |

Fits the starship crew theme — Uhura literally monitors communications channels for new signals.

### Option B: Scotty Skill Extension

Add a `selfhost-discovery` skill to Scotty's workspace. Simpler to implement but conflates hub/engineering responsibilities with discovery/research.

### Recommendation

**Option A** — a dedicated Uhura agent. Discovery is a distinct concern from Scotty's engineering/operations role. Uhura can run independently on a cron schedule and post findings to a dedicated channel without interrupting Scotty's other work.

## Agent Capabilities

### 1. Newsletter Digest Processing

**Trigger**: Weekly email arrives (Friday), forwarded to Rocket.Chat via n8n webhook or direct subscription.

**Workflow**:
1. Fetch latest newsletter via Ghost Content API: `GET /ghost/api/content/posts/?key=...&limit=1&fields=title,html,plaintext,published_at`
2. Parse plaintext/HTML for app mentions — look for GitHub URLs, Docker Hub references, app names
3. Cross-reference against icons `index.json` for canonical app names/categories
4. For each new app not in the lab's deployed list:
   a. Fetch GitHub repo metadata (stars, license, last commit, language)
   b. Search for `docker-compose.yml` in the repo
   c. Analyze compose file for dependencies (Postgres, Redis, MongoDB, etc.), ports, volumes
   d. Rate autodeploy difficulty: Easy / Medium / Hard based on criteria from candidates doc
   e. Score lab relevance based on gaps in current infrastructure
5. Post structured report to `#app-discovery` channel

**Output format** (Rocket.Chat message):
```
📡 Self-Host Weekly Digest — 2026-03-07

**3 new candidates identified:**

1. **AppName** ⭐ 12.3k | MIT | Go
   - Difficulty: Easy (single container, no deps)
   - Relevance: High — fills gap: [description]
   - Docker: `image/name:latest`, Port 8080, 1 volume
   - Compose: ✅ Found | Dependencies: None

2. **AnotherApp** ⭐ 5.1k | AGPL-3.0 | TypeScript
   - Difficulty: Medium (requires Postgres)
   - Relevance: Medium — similar to deployed Linkwarden
   - Docker: `ghcr.io/org/app:latest`, Port 3000, 2 volumes
   - Compose: ✅ Found | Dependencies: PostgreSQL

**Also mentioned**: [list of apps already deployed or previously assessed]
```

### 2. On-Demand Directory Search

**Trigger**: User asks in Rocket.Chat: "find me a self-hosted Notion alternative" or "what calendar apps are available?"

**Workflow**:
1. Use browser tool to navigate to `selfh.st/apps/`
2. Search/filter by the requested category or keyword
3. Take snapshot and extract app tiles (name, description, stars, tags)
4. For top results, fetch GitHub data and compose files
5. Return structured assessment

### 3. Release Monitoring (Phase 2)

**Trigger**: Cron (daily or weekly)

**Workflow**:
1. For each deployed app, check GitHub releases API for new versions
2. Compare against currently deployed image tags
3. Post update summary to `#app-discovery` or `#ops` channel

### 4. Icons Index Monitoring (Phase 2)

**Trigger**: Cron (weekly)

**Workflow**:
1. Fetch `index.json` from selfhst/icons repo
2. Diff against cached previous version
3. New entries = new apps tracked by selfh.st
4. Assess and report

## Autodeploy Difficulty Rating Criteria

The agent uses these heuristics to rate candidates (aligned with the autodeploy candidates doc):

| Rating | Criteria |
|--------|----------|
| **Easy** | Single container, 0-1 volumes, no database dependencies, minimal env vars |
| **Easy-Medium** | Single container, 1+ volumes, port conflict potential, or init scripts needed |
| **Medium** | Requires Postgres and/or Redis (existing shared infra), 1-3 volumes |
| **Medium-Hard** | Requires new infrastructure (MongoDB, new DB), or multi-container same-image |
| **Hard** | Multi-container with different images, custom builds, privileged containers, complex routing |

## Lab Relevance Scoring

| Factor | Weight | Description |
|--------|--------|-------------|
| Fills infrastructure gap | High | Provides capability not in the stack (e.g., SSO, CI/CD, calendar) |
| Uses existing deps | High | Postgres, Redis, or no deps preferred over new infrastructure |
| Complements deployed apps | Medium | Integrates with n8n, Rocket.Chat, Docmost, Gitea, etc. |
| Community health | Medium | Active commits, >1k stars, recent releases |
| Autodeploy difficulty | Low | Easier is slightly preferred but not decisive |
| Resource footprint | Low | Lighter is preferred but not decisive |

## Skill Definition

### SKILL.md (workspace skill for Uhura agent)

```markdown
---
name: selfhost-discovery
description: Monitor selfh.st newsletter and directory for new self-hosted app candidates. Assess autodeploy difficulty and lab relevance. Search the directory on demand.
metadata: {"openclaw":{"emoji":"📡"}}
---

# Self-Hosted App Discovery

You are the USS Octant's communications officer, monitoring all frequencies for new technology.

## Data Sources

- Ghost Content API: `https://selfh.st/ghost/api/content/posts/?key=a4717b8b11f6e5ae98a6b78e16`
- Icons index: `https://cdn.jsdelivr.net/gh/selfhst/icons@main/index.json`
- App directory: `https://selfh.st/apps/` (browser tool)
- GitHub: Fetch repos, compose files, metadata via web_fetch

## Assessment Workflow

1. Identify app mentions (newsletter or search results)
2. Fetch GitHub repo: stars, license, language, last commit
3. Find docker-compose.yml — extract: image, ports, volumes, dependencies
4. Rate difficulty: Easy / Easy-Medium / Medium / Medium-Hard / Hard
5. Score lab relevance against deployed apps and infrastructure gaps
6. Format structured report for Rocket.Chat

## Lab Context

Deployed apps: IT-Tools, Linkding, Fusion, Docmost, Linkwarden, Gitea, Rocket.Chat, NATS, FalkorDB, n8n, SearXNG, Excalidraw, Homepage, pgAdmin
Shared infra: PostgreSQL, MariaDB, Redis, Qdrant, CephFS, Traefik v3, LiteLLM, MinIO
Validated patterns: zero-config, SQLite+volume, Postgres+Redis, Postgres-only, MongoDB
Gaps: SSO/OIDC, full-text search, message broker, CI/CD, calendar, project management
```

## Tool Policy

```jsonc
{
  "profile": "coding",
  "allow": ["group:web", "browser", "group:fs", "message", "memory_search", "memory_get", "cron"],
  "deny": ["group:sessions", "canvas", "nodes", "gateway", "image"]
}
```

Key tools:
- **web_fetch**: Ghost API, GitHub API, icons index
- **browser**: selfh.st/apps/ directory search (client-rendered JS app requires browser)
- **web_search**: Fallback for finding Docker images, compose files, documentation
- **message**: Post reports to Rocket.Chat channels
- **cron**: Schedule weekly newsletter processing and release monitoring
- **memory**: Remember previously assessed apps to avoid duplicate reports

## n8n Integration

### Newsletter Forwarding Workflow

```
Email Trigger (selfh.st subscription)
    → Extract body text
    → HTTP POST to Rocket.Chat webhook
    → Posts to #app-discovery channel
    → Uhura agent triggers on new message
```

Alternative: n8n fetches Ghost API directly on a Friday cron, posts raw content to Rocket.Chat for Uhura to process.

## OpenClaw Configuration

### Agent Entry (add to openclaw.json `agents.list`)

```jsonc
{
  "id": "uhura",
  "workspace": "/home/node/.openclaw/workspace/uhura",
  "model": { "primary": "local/deepseek-v3.2" },
  "tools": {
    "profile": "coding",
    "allow": ["group:web", "browser", "group:fs", "message", "memory_search", "memory_get", "cron"],
    "deny": ["group:sessions", "canvas", "nodes", "gateway", "image"]
  }
}
```

### Workspace Files

```
/mnt/services/openclaw-gateway/workspaces/uhura/
├── IDENTITY.md    — Name, emoji, one-liner
├── SOUL.md        — Communications officer persona
├── AGENTS.md      — Operating rules, assessment workflow
├── TOOLS.md       — API endpoints, data sources, lab context
├── USER.md        — Demo context, audience
└── skills/
    └── selfhost-discovery/
        └── SKILL.md
```

### Rocket.Chat Channel

Create `#app-discovery` channel for agent reports. Pin the latest candidates doc summary for context.

## Implementation Phases

### Phase 1: Newsletter Intelligence (MVP)

- [ ] Subscribe to Self-Host Weekly newsletter (free email)
- [ ] Create Uhura agent config in openclaw.json
- [ ] Write SOUL.md, AGENTS.md, TOOLS.md, USER.md workspace files
- [ ] Write `selfhost-discovery` skill with Ghost API + GitHub workflow
- [ ] Create `#app-discovery` channel in Rocket.Chat
- [ ] Set up n8n workflow: email trigger → Rocket.Chat post
- [ ] Test: process the most recent 2-3 newsletters manually
- [ ] Deploy and validate weekly cron trigger

### Phase 2: On-Demand Search

- [ ] Enable browser tool for Uhura agent
- [ ] Add selfh.st/apps/ directory search to skill
- [ ] Test: "find me a self-hosted Calendly alternative"
- [ ] Add icons index.json diffing for new app detection

### Phase 3: Release Monitoring

- [ ] Add deployed app version tracking (image tags vs GitHub releases)
- [ ] Cron job for daily/weekly release checks
- [ ] Post update summaries to `#ops` or `#app-discovery`

### Phase 4: Knowledge Graph Integration

- [ ] Feed assessed apps into Graphiti as entities with relationships
- [ ] Enable "what apps are similar to X?" graph queries
- [ ] Connect to NATS for event-driven assessment triggers

## Success Metrics

- Agent surfaces at least 2-3 viable new candidates per month
- Candidates include correct difficulty rating and dependency analysis
- On-demand search returns relevant results within 60 seconds
- Zero false positives on "already deployed" checks
- Newsletter processing completes within 5 minutes of trigger

## Open Questions

1. **Ghost API stability**: The content API key is embedded in client JS — is it stable across site updates? Should we cache/refresh it?
2. **Browser tool availability**: Does the current OpenClaw container image include browser/Chromium? May need image update.
3. **Newsletter subscription email**: Which email address to subscribe? Dedicated mailbox or existing?
4. **Cron vs n8n trigger**: n8n already handles email workflows — is a cron in OpenClaw redundant?
5. **Agent naming**: Uhura fits the theme perfectly, but confirm with the crew roster plan in the gateway design doc.

## References

- [selfh.st](https://selfh.st/) — App directory and newsletter
- [selfhst/icons](https://github.com/selfhst/icons) — Structured app name index
- [Ghost Content API](https://ghost.org/docs/content-api/) — API documentation
- [Autodeploy candidates doc](../2026-02-27-autodeploy-candidates-design.md) — Current candidates and deployment status
- [OpenClaw gateway design](../2026-03-02-openclaw-gateway-design.md) — Agent roster and architecture
