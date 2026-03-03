# Autodeploy Skill Test Candidates

**Date**: 2026-02-27
**Goal**: Identify open source apps at easy/medium/hard difficulty levels to validate the `octant-autodeploy` skill and its helper skills (`octant-postgres`, `octant-redis`, `octant-consul-discovery`, `octant-volumes`, `octant-secrets-management`, `octant-validation`).

**Selection criteria**: Apps that are both genuinely useful in the lab AND good test subjects for the autodeploy workflow.

## Existing Infrastructure (as of 2026-02-27)

**Shared services**: PostgreSQL 16.2, MariaDB 10.11, Redis (redis.service.consul:6379), Qdrant, CephFS, Traefik v3, local registry at 192.168.122.1:5000

**Observability**: Grafana, Prometheus, Loki, Tempo, Alloy, Alertmanager, Gatus, Uptime Kuma, Arize Phoenix

**Apps**: n8n, SearXNG, Excalidraw, Homepage, nginx, pgAdmin, LiteLLM (pending)

---

## Easy Tier

Single container, no external dependencies. Tests basic compose-to-nomad conversion and Traefik routing.

### E1: IT-Tools (Top Pick)

- **Image**: `corentinth/it-tools:latest`
- **What**: ~90 browser-based dev utilities (JWT decoder, cron parser, hash generator, base64, UUID, regex tester, etc.)
- **Port**: 80
- **Volumes**: None
- **Config**: None — truly zero configuration, static web app
- **Why useful**: Replaces a dozen ad-laden online tools. Handy alongside pgAdmin, n8n, and general lab work.
- **Why good test**: Absolute simplest case. If the skill can't convert this, nothing else will work. Pure Traefik routing exercise.
- **Project**: https://github.com/CorentinTh/it-tools
- **Maintenance**: Nightly Docker builds active, Docker Hub shows recent pushes. Last stable tag Oct 2024 but CI is active.

### E2: Linkding

- **Image**: `sissbruecker/linkding:latest`
- **What**: Bookmark manager with tagging, auto-fetch of titles/descriptions, browser extensions, REST API
- **Port**: 9090
- **Volumes**: `/etc/linkding/data` (SQLite database)
- **Config**: `LD_SUPERUSER_NAME`, `LD_SUPERUSER_PASSWORD` to bootstrap admin
- **Why useful**: SearXNG finds things, Linkding saves them. No bookmark/link persistence tool in the stack.
- **Why good test**: Adds a volume mount and env vars on top of E1. Still single container.
- **Project**: https://github.com/sissbruecker/linkding
- **Maintenance**: v1.45.0 released Jan 6, 2026. 10.1k GitHub stars.

### E3: Fusion

- **Image**: `ghcr.io/0x2e/fusion:latest`
- **What**: Lightweight RSS reader (Go, SQLite-backed, single binary)
- **Port**: 8080
- **Volumes**: `/data` (SQLite database)
- **Config**: `FUSION_PASSWORD` (login password, username is always `fusion`)
- **Why useful**: No RSS reader in the stack. Complements SearXNG for ongoing feed monitoring.
- **Why good test**: Similar to Linkding — one volume, minimal env vars. Good for confirming consistency.
- **Project**: https://github.com/0x2E/fusion
- **Maintenance**: Active commits through Feb 2026. 2k GitHub stars.

---

## Medium Tier

Has 1+ dependencies (Postgres, Redis, or both). Tests the `octant-postgres` and `octant-redis` helper skills, Consul service discovery for DB/cache connections, and `octant-secrets-management` for credential provisioning.

### M1: Docmost (Top Pick)

- **Image**: `docmost/docmost:latest`
- **What**: Real-time collaborative wiki and documentation platform (Confluence/Notion alternative). Supports spaces, page hierarchies, comments, history, full-text search, embedded diagrams (Draw.io, Excalidraw, Mermaid).
- **Port**: 3000
- **Dependencies**: PostgreSQL (required), Redis (required)
- **Volumes**: `/app/data/storage` (file attachments; S3 optional)
- **Config**: `APP_URL`, `APP_SECRET`, `DATABASE_URL`, `REDIS_URL`
- **Why useful**: Knowledge base for lab runbooks, AI experiment docs, infrastructure how-tos. Excalidraw embed integration pairs with the already-deployed Excalidraw instance.
- **Why good test**: Exercises both `octant-postgres` (create DB + user) and `octant-redis` (allocate DB number). Clean compose — stripping to 1 container for shared-infra lab is straightforward. App handles its own schema migrations on first start.
- **Project**: https://github.com/docmost/docmost | https://docmost.com
- **Maintenance**: v0.25.3 released Feb 10, 2026. 19k GitHub stars, 47 releases.
- **Compose reference**:
  ```yaml
  services:
    docmost:
      image: docmost/docmost:latest
      environment:
        APP_URL: "https://docmost.lab.example.com"
        APP_SECRET: "REPLACE_WITH_LONG_SECRET"
        DATABASE_URL: "postgresql://docmost:password@postgres.service.consul:5432/docmost"
        REDIS_URL: "redis://redis.service.consul:6379"
      ports:
        - "3000:3000"
      volumes:
        - docmost_storage:/app/data/storage
  ```

### M2: Paperless-ngx

- **Image**: `ghcr.io/paperless-ngx/paperless-ngx:latest`
- **What**: Document management system with OCR. Ingests scanned docs/PDFs, runs OCR, auto-tags, makes everything full-text searchable.
- **Port**: 8000
- **Dependencies**: PostgreSQL (recommended over SQLite), Redis (required — Celery task broker)
- **Volumes**: `/usr/src/paperless/data`, `/usr/src/paperless/media`, `/usr/src/paperless/consume`
- **Config**: `PAPERLESS_REDIS`, `PAPERLESS_DBENGINE=postgres`, `PAPERLESS_DBHOST`, `PAPERLESS_DBPORT`, `PAPERLESS_DBNAME`, `PAPERLESS_DBUSER`, `PAPERLESS_DBPASS`
- **Optional sidecars**: Gotenberg (`gotenberg/gotenberg:8`) and Tika (`apache/tika:latest-full`) for Office doc support — not required for PDF/image processing.
- **Why useful**: Pairs with n8n for automated document ingestion (n8n watches mailbox, saves to consume folder). Organizes bills, manuals, scanned docs.
- **Why good test**: Core is single container with external Postgres+Redis. Three volume mounts add volume management complexity. Optional Gotenberg/Tika sidecars could be a phase 2 exercise.
- **Project**: https://github.com/paperless-ngx/paperless-ngx
- **Maintenance**: Actively maintained, frequent releases, large community.

### M3: Gitea

- **Image**: `gitea/gitea:latest` or `docker.gitea.com/gitea:latest`
- **What**: Self-hosted Git forge (GitHub alternative) with web UI, PRs, issues, wiki, CI/CD via Gitea Actions, container registry.
- **Port**: 3000 (HTTP), 2222 (SSH — optional)
- **Dependencies**: PostgreSQL (recommended), Redis (optional for caching/sessions)
- **Volumes**: `/data` (repos, config, attachments, LFS)
- **Config**: Uses `GITEA__section__key` double-underscore env var pattern mapping to `app.ini`
- **Why useful**: Private Git remote for lab IaC, Nomad jobs, playbooks, experiment scripts. Built-in container registry.
- **Why good test**: Clean single-container deploy for web-only. SSH port handling (TCP routing in Traefik/Nomad) adds medium+ complexity. The env var config pattern is well-documented but unusual.
- **Project**: https://github.com/go-gitea/gitea
- **Maintenance**: v1.25.4 current. Very active, daily nightly builds.

### M4: Linkwarden

- **Image**: `ghcr.io/linkwarden/linkwarden:latest`
- **What**: Collaborative bookmark and web archive manager. Saves pages as screenshots, PDFs, HTML snapshots. Tags, collections, full-text search.
- **Port**: 3000
- **Dependencies**: PostgreSQL only (no Redis!)
- **Volumes**: `/data/data` (archived page content)
- **Config**: `DATABASE_URL`, `NEXTAUTH_SECRET`, `NEXTAUTH_URL`
- **Optional**: Meilisearch for full-text search (separate container, no external deps of its own)
- **Why useful**: Like Linkding but with web archiving. SearXNG finds things, Linkwarden saves and archives them.
- **Why good test**: Simplest medium candidate — Postgres only. `NEXTAUTH_URL` must match the externally accessible URL exactly (common Traefik gotcha).
- **Project**: https://github.com/linkwarden/linkwarden
- **Maintenance**: v2.13.5 current (Jan 2026). Active development.

---

## Hard Tier

Multi-container, complex orchestration, potentially custom Dockerfile builds. Tests the full autodeploy pipeline including build-and-push, multi-task Nomad jobs, privileged containers, and non-HTTP routing.

### H1: Windmill (Top Pick)

- **Image**: `ghcr.io/windmill-labs/windmill:main` (server + workers, same image, different `MODE`)
- **What**: Developer platform for scripts, flows (multi-step workflows), apps (low-code UI), and scheduled jobs. Supports Python, TypeScript/Bun, Go, Bash, Rust, PHP, Java. Code-first alternative to n8n.
- **Port**: 8000 (app), 3001 (LSP)
- **Dependencies**: PostgreSQL only — uses Postgres as state store AND job queue (LISTEN/NOTIFY, no Redis needed)
- **Containers**:
  - Server (`MODE=server`) — API, scheduler, web UI
  - 3x Workers (`MODE=worker`, `WORKER_GROUP=default`) — execute scripts in sandboxed subprocesses
  - Native worker (`MODE=worker`, `WORKER_GROUP=native`, `NATIVE_MODE=true`) — 8 lightweight workers for HTTP/SQL/small jobs
  - LSP server (`ghcr.io/windmill-labs/windmill-lsp:latest`) — Monaco editor code intelligence
  - Caddy (`ghcr.io/windmill-labs/caddy-l4:latest`) — internal L4 proxy (replaceable with Traefik config)
- **Volumes**: Worker dependency cache (`/tmp/windmill/cache`) for pip/npm packages — should be persistent and shared
- **What makes it hard**:
  1. **Worker replica groups**: Nomad's job model isn't Docker Compose `replicas: 3`. Need `count = 3` task groups or multiple named groups with different worker group tags.
  2. **Privileged workers**: Need `privileged = true` or specific Linux capabilities for PID namespace sandboxing (`--unshare-pid`). Requires Nomad client config allowlisting.
  3. **LSP WebSocket routing**: Port 3001 needs Traefik path-based WebSocket routing (`/ws/`), different from standard host-based routing.
  4. **Caddy vs Traefik decision**: Official compose uses Caddy as internal router. Must either keep it as internal service or replace with Traefik routing rules.
  5. **Shared dependency cache**: Cache volume should be shared across workers on CephFS — non-trivial with multiple Nomad task instances.
- **Why useful**: Powerful code-first automation platform complementing n8n. Can orchestrate calls to LiteLLM, Qdrant, Postgres, Arize Phoenix from Python/TS scripts with built-in secret manager and audit log.
- **Project**: https://github.com/windmill-labs/windmill
- **Maintenance**: Actively maintained, both Helm chart and docker-compose available.
- **New infra deps**: None — uses only Postgres (already deployed).

### H2: Plane

- **Image**: ALL built from source Dockerfiles — `makeplane/plane-frontend`, `plane-space`, `plane-api`, `plane-worker`, `plane-beat-worker`, `plane-migrator`, `plane-live`, custom nginx
- **What**: Modern project management platform (Jira/Linear alternative). Issues, sprints, roadmaps, wiki, analytics.
- **Port**: 80 (nginx proxy)
- **Dependencies**: PostgreSQL + Redis + **RabbitMQ** (new)
- **Containers**: 11 total (6 app images built from Dockerfiles, plus PG, Redis, RabbitMQ, nginx, migrator)
- **What makes it hard**:
  1. **6+ custom Dockerfile builds**: Every Plane service has its own Dockerfile. Must build all, tag, and push to 192.168.122.1:5000 before jobs can run.
  2. **Migrator init pattern**: One-shot Django `manage.py migrate` container. Must model as Nomad `prestart` lifecycle hook or batch job.
  3. **Celery worker + beat interplay**: Same image, different commands. Beat schedules into RabbitMQ; worker consumes.
  4. **RabbitMQ**: Not in existing stack — adds a new stateful service.
  5. **Inter-service communication**: live ↔ API ↔ Postgres ↔ Redis, workers ↔ RabbitMQ — complex Consul mesh.
- **Why useful**: Issue tracker and sprint board for managing lab projects.
- **Project**: https://github.com/makeplane/plane
- **Maintenance**: Helm chart last updated Feb 24, 2026. Active development.
- **New infra deps**: RabbitMQ (new service to deploy and manage).

### H3: Outline

- **Image**: `docker.getoutline.com/outlinewiki/outline:latest`
- **What**: Notion-like team wiki with real-time collaborative editing, rich block editor, full-text search.
- **Port**: 3000
- **Dependencies**: PostgreSQL + Redis + S3 (mandatory) + **OIDC provider** (mandatory — no built-in username/password auth)
- **What makes it hard**:
  1. **Mandatory OIDC**: No built-in auth. Must configure GitHub OAuth or deploy Authentik/Keycloak.
  2. **S3 CORS**: MinIO/CephFS bucket needs specific CORS rules for browser file uploads.
  3. **URL consistency**: `URL`, `AWS_S3_UPLOAD_BUCKET_URL`, and Traefik host header must all match exactly.
  4. **Real-time collab**: Redis pub/sub for document sync; WebSocket sticky sessions needed if scaling to multiple instances.
- **Why useful**: Beautiful wiki for lab documentation.
- **Project**: https://github.com/outline/outline
- **Maintenance**: Actively maintained. No official Helm chart; docker-compose available.
- **New infra deps**: OIDC provider (GitHub OAuth app or self-hosted Authentik).

### H4: Gitea + act_runner + DinD

- **Image**: `docker.gitea.com/gitea:1.25.x` + `gitea/act_runner:latest` + `docker:dind`
- **What**: Full Git forge with CI/CD pipeline capable of building and pushing images.
- **Dependencies**: PostgreSQL + Redis + Docker-in-Docker
- **What makes it hard**:
  1. **DinD**: Runner needs privileged containers or DinD sidecar for building Docker images in CI. Painful in Nomad.
  2. **SSH TCP routing**: Git-over-SSH needs Traefik TCP entrypoint, not just HTTP.
  3. **Runner registration bootstrap**: Runner token generated from Gitea API at runtime — ordering dependency.
  4. **Self-referential**: Its own CI can build and push images to the local registry, making it both the tool and the test.
- **Why useful**: Private CI/CD for lab infrastructure.
- **Project**: https://github.com/go-gitea/gitea
- **Maintenance**: Very active. Both Helm chart and docker-compose available.
- **New infra deps**: Docker-in-Docker socket.

---

## Knowledge Layer

Independent services forming an event-driven knowledge infrastructure. These can be deployed standalone and later wired together (e.g., NATS feeding events into Graphiti for knowledge graph construction).

### K1: NATS (with JetStream)

- **Image**: `nats:latest` (official Docker Hub image)
- **What**: High-performance messaging system. Core NATS provides pub/sub and request/reply. JetStream adds persistence, at-least-once delivery, key-value store, and object store. Lightweight alternative to Kafka/RabbitMQ — single binary, ~20MB.
- **Ports**: 4222 (client), 8222 (HTTP monitoring), 6222 (cluster routing — only if clustering)
- **Dependencies**: None
- **Volumes**: `/data/jetstream` (JetStream persistence — only needed if JetStream enabled)
- **Config**: Can run zero-config for basic pub/sub. JetStream requires a config file or `--jetstream` flag with a storage directory. Monitoring via `--http_port 8222`.
- **Health check**: `http://localhost:8222/healthz`
- **Why useful**: Event bus for the lab. Enables decoupled communication between services — n8n, Windmill, Graphiti, and custom scripts can publish/subscribe to events without point-to-point wiring. JetStream's KV store is useful for lightweight configuration sharing. Could replace RabbitMQ as the messaging layer if Plane is ever deployed.
- **Why good test**: Without JetStream, this is E-tier (single container, no volumes, no dependencies). With JetStream persistence, it's a light Medium — adds a volume and a config file mount. The monitoring port provides a good Traefik routing + health check exercise.
- **Tier**: **Easy** (core) / **Easy-Medium** (with JetStream persistence)
- **Project**: <https://github.com/nats-io/nats-server>
- **Maintenance**: Actively maintained by Synadia. Official Docker image, frequent releases. CNCF incubating project.
- **New infra deps**: None
- **Compose reference**:

  ```yaml
  services:
    nats:
      image: nats:latest
      command: ["--jetstream", "--store_dir", "/data/jetstream", "--http_port", "8222"]
      ports:
        - "4222:4222"
        - "8222:8222"
      volumes:
        - nats_data:/data/jetstream
  ```

### K2: FalkorDB

- **Image**: `falkordb/falkordb:latest` (combined server + browser UI)
- **What**: High-performance graph database optimized for GraphRAG and AI/ML workloads. Redis-protocol-compatible (uses Redis as its storage engine with the FalkorDB module loaded). Supports Cypher queries via `GRAPH.QUERY`. Includes a web browser UI on port 3000.
- **Ports**: 6379 (Redis protocol — graph queries), 3000 (web browser UI)
- **Dependencies**: None
- **Volumes**: `/data` (graph persistence)
- **Config**: `REDIS_ARGS` for Redis-level config (password, appendonly, maxmemory). `FALKORDB_ARGS` for graph engine tuning (thread count, cache size, timeouts).
- **Health check**: `redis-cli ping`
- **Port conflict note**: Uses Redis protocol on 6379 but is NOT the existing Redis instance. Must bind to a different host port (e.g., 6380) or use Consul service discovery at `falkordb.service.consul:6379` with Nomad network isolation.
- **Why useful**: Purpose-built graph database for knowledge graphs, relationship queries, and GraphRAG patterns. Required by Graphiti (K3). FalkorDB is significantly lighter than Neo4j (~100MB image vs ~500MB) and uses familiar Redis protocol, which aligns better with the existing Redis tooling in the lab.
- **Why good test**: Single container with persistence volume. The port conflict with existing Redis is a realistic deployment challenge — tests Nomad network namespace isolation and Consul service registration with a non-standard service name.
- **Tier**: **Easy-Medium** (single container, but port conflict management adds complexity)
- **Project**: <https://github.com/FalkorDB/FalkorDB>
- **Maintenance**: Active development, frequent Docker Hub pushes. Used by Graphiti as default backend.
- **New infra deps**: None (standalone graph DB)
- **Compose reference**:

  ```yaml
  services:
    falkordb:
      image: falkordb/falkordb:latest
      ports:
        - "6380:6379"
        - "3001:3000"
      environment:
        - REDIS_ARGS=--requirepass ${FALKORDB_PASSWORD:-changeme} --appendonly yes
        - FALKORDB_ARGS=THREAD_COUNT 4
      volumes:
        - falkordb_data:/data
  ```

### K3: Graphiti

- **Image**: `zepai/graphiti:latest` (FastAPI server wrapping graphiti-core)
- **What**: Temporal knowledge graph framework for AI agents. Ingests unstructured text ("episodes"), extracts entities and relationships via LLM, builds a queryable knowledge graph with temporal awareness. Provides graph-based search with reranking. Exposes REST API and MCP server for integration with Claude, Cursor, and other AI tools.
- **Port**: 8000
- **Dependencies**: **FalkorDB** (K2, required — graph storage) + **LLM API** (required — entity extraction and embedding)
- **Volumes**: None (stateless — all state lives in FalkorDB)
- **Config**:
  - `OPENAI_API_KEY` or equivalent LLM provider key (can point at LiteLLM for local proxy)
  - `FALKORDB_URI=redis://falkordb.service.consul:6379` (or Neo4j bolt URI)
  - `FALKORDB_PASSWORD` (if set on FalkorDB)
  - `DATABASE_PROVIDER=falkordb` (default)
  - Optional: `--llm-provider` (openai, anthropic, gemini, groq), `--embedder-provider`, `--model`, `--group-id`
- **LLM integration note**: Graphiti requires an LLM for entity/relationship extraction. It supports OpenAI, Anthropic, Gemini, Groq, and Azure OpenAI. In this lab, it can point at the existing LiteLLM proxy (`litellm.service.consul`) using the OpenAI-compatible API, routing to whatever backend models are configured.
- **Why useful**: Builds a persistent knowledge graph from conversations, documents, and events. AI agents (via MCP) can query the graph for context — "what do I know about X?" with temporal awareness. Pairs with NATS (events feed episodes into the graph) and the existing LiteLLM/Arize Phoenix observability stack.
- **Why good test**: Exercises inter-service dependency ordering (FalkorDB must be healthy before Graphiti starts). Tests Consul service discovery for a non-standard backend (FalkorDB vs Postgres/Redis). The LLM API dependency via LiteLLM tests service-to-service connectivity through Consul DNS. Stateless container with all state in an external database — clean separation of concerns.
- **Tier**: **Medium** (single container, but depends on FalkorDB + LLM API)
- **Project**: <https://github.com/getzep/graphiti>
- **Maintenance**: 20k+ GitHub stars, v1.0 MCP server released. Active development, automated Docker Hub releases matching graphiti-core PyPI versions.
- **New infra deps**: FalkorDB (K2) — must be deployed first. LiteLLM should be operational for LLM access.
- **Compose reference**:

  ```yaml
  services:
    graphiti:
      image: zepai/graphiti:latest
      ports:
        - "8000:8000"
      environment:
        - OPENAI_API_KEY=${OPENAI_API_KEY}
        - OPENAI_BASE_URL=http://litellm.service.consul:4000/v1
        - FALKORDB_URI=redis://falkordb.service.consul:6379
        - FALKORDB_PASSWORD=${FALKORDB_PASSWORD}
        - DATABASE_PROVIDER=falkordb
  ```

### Knowledge Layer Prerequisites

| Service      | Prerequisites                        | Notes                                                              |
| ------------ | ------------------------------------ | ------------------------------------------------------------------ |
| **NATS**     | None                                 | Fully independent. Deploy anytime.                                 |
| **FalkorDB** | None                                 | Independent, but watch for port 6379 conflict with existing Redis. |
| **Graphiti** | FalkorDB (K2) + LiteLLM (operational) | LiteLLM is listed as "pending" — should be deployed first.        |

### Knowledge Layer Deployment Order

1. **NATS** — independent, zero-config baseline
2. **FalkorDB** — independent, adds graph DB capability
3. **Graphiti** — depends on FalkorDB + LiteLLM

These three can be interleaved with the main deployment order. NATS and FalkorDB can deploy in parallel with any Easy/Medium tier candidates. Graphiti should come after FalkorDB and LiteLLM are confirmed operational.

---

## Top Picks

| Tier | Pick | Rationale |
|------|------|-----------|
| **Easy** | IT-Tools | Zero-config baseline. If the skill can't handle this, nothing else will work. |
| **Medium** | Docmost | Exercises both `octant-postgres` and `octant-redis` helper skills. Clean compose. Immediately useful as a lab wiki. |
| **Hard** | Windmill | Complex worker architecture, privileged containers, WebSocket routing — but no new infrastructure deps (Postgres only). Genuinely useful as a code-first automation platform alongside n8n. |
| **Knowledge** | NATS + FalkorDB + Graphiti | Event bus + graph DB + knowledge graph. Three independent services that compose into an AI knowledge layer. |

**Runner-up picks**: Linkding (easy), Gitea (medium), Plane (hardest possible test — 6 custom Dockerfile builds).

---

## Deployment Order Recommendation

1. **IT-Tools** — validate basic skill functionality
2. **Linkding** — add volume management
3. **NATS** — zero-dep messaging, validates easy tier with non-HTTP ports
4. **FalkorDB** — graph DB, tests port conflict management with existing Redis
5. **Docmost** — add Postgres + Redis integration
6. **Graphiti** — knowledge graph, tests inter-service deps (FalkorDB + LiteLLM)
7. **Windmill** — full complexity test

This progression builds confidence in the skill incrementally, with each deployment exercising new capabilities on top of the previous ones. The knowledge layer services (NATS, FalkorDB, Graphiti) are interleaved at natural complexity breakpoints rather than grouped together.
