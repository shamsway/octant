# Autodeploy Skill Test Candidates

**Date**: 2026-02-27
**Goal**: Identify open source apps at easy/medium/hard difficulty levels to validate the `octant-autodeploy` skill and its helper skills (`octant-postgres`, `octant-redis`, `octant-consul-discovery`, `octant-volumes`, `octant-secrets-management`, `octant-validation`).

**Selection criteria**: Apps that are both genuinely useful in the lab AND good test subjects for the autodeploy workflow.

## Existing Infrastructure (as of 2026-02-27)

**Shared services**: PostgreSQL 16.2, MariaDB 10.11, Redis (redis.service.consul:6379), Qdrant, CephFS, Traefik v3, local registry at 192.168.122.1:5000

**Observability**: Grafana, Prometheus, Loki, Tempo, Alloy, Alertmanager, Gatus, Uptime Kuma, Arize Phoenix

**Apps**: n8n, SearXNG, Excalidraw, Homepage, nginx, pgAdmin, LiteLLM, IT-Tools, Linkding, Fusion, Docmost, Linkwarden, Gitea, Rocket.Chat

---

## Easy Tier

Single container, no external dependencies. Tests basic compose-to-nomad conversion and Traefik routing.

### E1: IT-Tools (Top Pick) — DEPLOYED

- **Image**: `corentinth/it-tools:latest`
- **What**: ~90 browser-based dev utilities (JWT decoder, cron parser, hash generator, base64, UUID, regex tester, etc.)
- **Port**: 80
- **Volumes**: None
- **Config**: None — truly zero configuration, static web app
- **Why useful**: Replaces a dozen ad-laden online tools. Handy alongside pgAdmin, n8n, and general lab work.
- **Why good test**: Absolute simplest case. If the skill can't convert this, nothing else will work. Pure Traefik routing exercise.
- **Project**: https://github.com/CorentinTh/it-tools
- **Maintenance**: Nightly Docker builds active, Docker Hub shows recent pushes. Last stable tag Oct 2024 but CI is active.

### E2: Linkding — DEPLOYED

- **Image**: `sissbruecker/linkding:latest`
- **What**: Bookmark manager with tagging, auto-fetch of titles/descriptions, browser extensions, REST API
- **Port**: 9090
- **Volumes**: `/etc/linkding/data` (SQLite database)
- **Config**: `LD_SUPERUSER_NAME`, `LD_SUPERUSER_PASSWORD` to bootstrap admin
- **Why useful**: SearXNG finds things, Linkding saves them. No bookmark/link persistence tool in the stack.
- **Why good test**: Adds a volume mount and env vars on top of E1. Still single container.
- **Project**: https://github.com/sissbruecker/linkding
- **Maintenance**: v1.45.0 released Jan 6, 2026. 10.1k GitHub stars.

### E3: Fusion — DEPLOYED

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

### M1: Docmost (Top Pick) — DEPLOYED

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
        APP_URL: "https://docmost.lab.shamsway.net"
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

### M3: Gitea — DEPLOYED

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

### M4: Linkwarden — DEPLOYED

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

### K2: FalkorDB — DEPLOYED

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
- **Dependencies**: **Neo4j** (K4, required — graph storage) + **LLM API** (required — entity extraction and embedding)
- **Volumes**: None (stateless — all state lives in Neo4j)
- **Config**:
  - `OPENAI_API_KEY` or equivalent LLM provider key (can point at LiteLLM for local proxy)
  - `NEO4J_URI=bolt://neo4j.service.consul:7687`
  - `NEO4J_USER=neo4j`
  - `NEO4J_PASSWORD` (Neo4j auth password)
  - Optional: `--llm-provider` (openai, anthropic, gemini, groq), `--embedder-provider`, `--model`, `--group-id`
- **LLM integration note**: Graphiti requires an LLM for entity/relationship extraction. It supports OpenAI, Anthropic, Gemini, Groq, and Azure OpenAI. In this lab, it can point at the existing LiteLLM proxy (`litellm.service.consul`) using the OpenAI-compatible API, routing to whatever backend models are configured.
- **Why useful**: Builds a persistent knowledge graph from conversations, documents, and events. AI agents (via MCP) can query the graph for context — "what do I know about X?" with temporal awareness. Pairs with NATS (events feed episodes into the graph) and the existing LiteLLM/Arize Phoenix observability stack.
- **Why good test**: Exercises inter-service dependency ordering (Neo4j must be healthy before Graphiti starts). Tests Consul service discovery for Bolt protocol. The LLM API dependency via LiteLLM tests service-to-service connectivity through Consul DNS. Stateless container with all state in an external database — clean separation of concerns.
- **Tier**: **Medium** (single container, but depends on Neo4j + LLM API)
- **Project**: <https://github.com/getzep/graphiti>
- **Maintenance**: 20k+ GitHub stars, v1.0 MCP server released. Active development, automated Docker Hub releases matching graphiti-core PyPI versions.
- **New infra deps**: Neo4j (K4) — must be deployed first. LiteLLM should be operational for LLM access.
- **Docker image note**: The official `zepai/graphiti:latest` image only supports Neo4j (not FalkorDB) as of 2026-03. FalkorDB support exists in the `graphiti-core` Python library but has not been added to the server Docker image ([tracking issue](https://github.com/getzep/graphiti/issues/749)). The container also requires `user = "root"` override because `uv` is installed in `/root/.local/bin/` but the Dockerfile sets `USER app`.
- **Compose reference**:

  ```yaml
  services:
    graphiti:
      image: zepai/graphiti:latest
      user: root
      ports:
        - "8000:8000"
      environment:
        - OPENAI_API_KEY=${OPENAI_API_KEY}
        - OPENAI_BASE_URL=http://litellm.service.consul:4000/v1
        - NEO4J_URI=bolt://neo4j.service.consul:7687
        - NEO4J_USER=neo4j
        - NEO4J_PASSWORD=${NEO4J_PASSWORD}
  ```

### K4: Neo4j

- **Image**: `neo4j:5-community` (official Docker Hub image, Community Edition)
- **What**: Industry-standard graph database with native Cypher query language, ACID transactions, and full-text search. Required by Graphiti's official Docker server image for knowledge graph storage.
- **Ports**: 7474 (HTTP browser UI), 7687 (Bolt protocol — client connections)
- **Dependencies**: None
- **Volumes**: `/data` (graph data), `/logs` (server logs)
- **Config**:
  - `NEO4J_AUTH=neo4j/<password>` (initial admin credentials, format `user/password`)
  - `NEO4J_PLUGINS=["apoc"]` (optional — APOC procedures for advanced graph operations)
  - `NEO4J_server_memory_heap_initial__size=512m` (JVM heap — tune for available memory)
  - `NEO4J_server_memory_heap_max__size=512m`
  - `NEO4J_server_memory_pagecache_size=256m`
- **Health check**: `http://localhost:7474` (browser UI returns 200)
- **Why useful**: Required backend for Graphiti's official Docker image. Also useful standalone for Cypher-based graph queries, relationship modeling, and knowledge graph exploration via the built-in browser UI.
- **Tier**: **Easy-Medium** (single container, but JVM memory tuning and two ports add minor complexity)
- **Project**: <https://github.com/neo4j/neo4j>
- **Maintenance**: Actively maintained. Official Docker image with regular releases. Community Edition is free and sufficient for lab use.
- **New infra deps**: None (standalone graph DB)
- **Resource note**: Neo4j is a JVM application — allocate at least 1024MB memory (512MB heap + 256MB page cache + overhead). Heavier than FalkorDB (~500MB image vs ~100MB) but well-supported by Graphiti.
- **Compose reference**:

  ```yaml
  services:
    neo4j:
      image: neo4j:5-community
      ports:
        - "7474:7474"
        - "7687:7687"
      environment:
        - NEO4J_AUTH=neo4j/${NEO4J_PASSWORD:-changeme}
        - NEO4J_PLUGINS=["apoc"]
        - NEO4J_server_memory_heap_initial__size=512m
        - NEO4J_server_memory_heap_max__size=512m
        - NEO4J_server_memory_pagecache_size=256m
      volumes:
        - neo4j_data:/data
        - neo4j_logs:/logs
  ```

### Knowledge Layer Prerequisites

| Service      | Prerequisites                      | Notes                                                              |
| ------------ | ---------------------------------- | ------------------------------------------------------------------ |
| **NATS**     | None                               | Fully independent. Deploy anytime. **Deployed 2026-03-02.**       |
| **FalkorDB** | None                               | Independent. Deployed for future use (GraphRAG, Redis-protocol graph queries). **Deployed 2026-03-02.** |
| **Neo4j**    | None                               | Independent. Required by Graphiti's official Docker image.         |
| **Graphiti** | Neo4j (K4) + LiteLLM (operational) | Official Docker image only supports Neo4j, not FalkorDB ([#749](https://github.com/getzep/graphiti/issues/749)). Requires `user: root` override. |

### Knowledge Layer Deployment Order

1. **NATS** — independent, zero-config baseline (done)
2. **FalkorDB** — independent, adds graph DB capability (done)
3. **Neo4j** — independent, required by Graphiti
4. **Graphiti** — depends on Neo4j + LiteLLM

NATS and FalkorDB can deploy in parallel with any Easy/Medium tier candidates. Neo4j should be deployed before Graphiti. Graphiti Terraform config is ready at `terraform/graphiti/` — just needs Neo4j running and its Nomad variable (`nomad/jobs/neo4j` with `NEO4J_PASSWORD`) set.

---

## Team Chat Layer

Self-hosted team chat platforms (Slack/Discord alternatives) for demos and daily use. Key requirement: bot/webhook/agent support so tools like OpenClaw can interact via the platform. Eliminates reliance on third-party chat services.

### C1: Mattermost (Top Pick)

- **Image**: `mattermost/mattermost-team-edition:latest`
- **What**: Open-source Slack alternative with channels, DMs, threads, file sharing, audio/video calls, and a rich plugin ecosystem. Team Edition is fully open-source (MIT). Strong bot account and webhook support — OpenClaw connects via incoming/outgoing webhooks or bot tokens. Built-in Bleve full-text search (no Elasticsearch needed).
- **Port**: 8065
- **Dependencies**: PostgreSQL (required — uses existing shared instance)
- **Volumes**: `/mattermost/data` (file uploads, plugins), `/mattermost/config` (server config), `/mattermost/logs`, `/mattermost/bleve-indexes` (search indexes)
- **Config**: `MM_SQLSETTINGS_DATASOURCE` (Postgres connection string), `MM_SERVICESETTINGS_SITEURL` (public URL), `MM_SQLSETTINGS_DRIVERNAME=postgres`
- **Agent/bot support**: Bot accounts with API tokens, incoming/outgoing webhooks, slash commands, plugin API (Go), REST API. OpenClaw supports Mattermost as a gateway. Integrations with n8n via webhook nodes.
- **Why useful**: Team chat for lab collaboration and demos. Bots/agents (OpenClaw, n8n workflows) can post updates, respond to commands, and automate tasks directly in channels. Mobile apps available. Pairs with n8n for ChatOps-style automation.
- **Why good test**: Exercises `octant-postgres` (create DB + user) like Docmost, but without Redis. Four volume mounts add volume management complexity. The `SITEURL` must match Traefik's external URL exactly (common gotcha). Good Medium-tier candidate.
- **Tier**: **Medium** (single container, but Postgres dependency + multiple volumes + URL config)
- **Project**: <https://github.com/mattermost/mattermost>
- **Maintenance**: Very active — 35.6k GitHub stars, daily commits. Docker images for both Team and Enterprise editions.
- **New infra deps**: None — uses existing PostgreSQL
- **Compose reference**:

  ```yaml
  services:
    mattermost:
      image: mattermost/mattermost-team-edition:latest
      ports:
        - "8065:8065"
      environment:
        - MM_SQLSETTINGS_DRIVERNAME=postgres
        - MM_SQLSETTINGS_DATASOURCE=postgres://mattermost:password@postgres.service.consul:5432/mattermost?sslmode=disable&connect_timeout=10
        - MM_SERVICESETTINGS_SITEURL=https://mattermost.lab.shamsway.net
        - MM_BLEVESETTINGS_INDEXDIR=/mattermost/bleve-indexes
        - MM_BLEVESETTINGS_ENABLEINDEXING=true
        - MM_BLEVESETTINGS_ENABLESEARCHING=true
        - MM_BLEVESETTINGS_ENABLEAUTOCOMPLETE=true
      volumes:
        - mattermost_data:/mattermost/data
        - mattermost_config:/mattermost/config
        - mattermost_logs:/mattermost/logs
        - mattermost_bleve:/mattermost/bleve-indexes
  ```

### C2: Rocket.Chat — DEPLOYED

- **Image**: `rocket.chat:latest` (or `registry.rocket.chat/rocketchat/rocket.chat:latest`)
- **What**: Feature-rich open-source team chat with channels, DMs, threads, video conferencing, marketplace for apps/integrations, and built-in AI capabilities. 44.8k GitHub stars. Supports omnichannel (live chat widget for external users), federation, and E2E encryption.
- **Port**: 3000
- **Dependencies**: **MongoDB** (required — not in existing stack)
- **Volumes**: `/app/uploads` (file attachments)
- **Config**: `ROOT_URL`, `MONGO_URL`, `MONGO_OPLOG_URL`, `PORT`
- **Agent/bot support**: REST API, Realtime API (WebSocket), incoming/outgoing webhooks, Hubot adapter, custom apps via Rocket.Chat Apps Engine (TypeScript). Has a dedicated MCP server (`elieworkspace/rocketchat-mcp`). OpenClaw can connect via webhooks. Built-in AI app with RAG pipeline support.
- **Why useful**: More feature-rich than Mattermost — omnichannel support, app marketplace, and built-in AI integration. Better fit if external-facing chat (live support widget) is desired.
- **Why good test**: MongoDB is a new infrastructure dependency not in the existing stack. MongoDB requires replica set initialization (oplog), which adds orchestration complexity. Tests the autodeploy skill's ability to handle non-Postgres databases.
- **Tier**: **Medium-Hard** (app container is simple, but MongoDB with replica set is new infrastructure)
- **Project**: <https://github.com/RocketChat/Rocket.Chat>
- **Maintenance**: Very active — 44.8k GitHub stars, daily commits. Official Docker images and Helm charts.
- **New infra deps**: MongoDB (new service to deploy and manage — requires replica set config)
- **Compose reference**:

  ```yaml
  services:
    rocketchat:
      image: rocket.chat:latest
      ports:
        - "3000:3000"
      environment:
        - ROOT_URL=https://rocketchat.lab.shamsway.net
        - PORT=3000
        - MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0
        - MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0
      volumes:
        - rocketchat_uploads:/app/uploads
      depends_on:
        - mongodb
    mongodb:
      image: mongo:7
      command: mongod --replSet rs0 --oplogSize 128
      volumes:
        - mongodb_data:/data/db
  ```

### Team Chat Layer Recommendation

| Service        | Prerequisites              | Notes                                                             |
| -------------- | -------------------------- | ----------------------------------------------------------------- |
| **Mattermost** | PostgreSQL (existing)      | Single container, zero new infra deps. Best starting point.       |
| **Rocket.Chat** | MongoDB (new)             | Richer features (omnichannel, AI app), but adds new DB to manage. |

**Status**: **Rocket.Chat deployed** (2026-03) with MongoDB and OpenClaw gateway integration. Mattermost remains an option if a lighter Postgres-only alternative is desired.

---

## Infrastructure Layer

Standalone infrastructure services that expand the lab's shared service catalog. Each adds a new capability useful to multiple applications and provides diverse deployment patterns for testing the autodeploy skill.

### I1: MongoDB

- **Image**: `mongo:7` (official Docker Hub image)
- **What**: Document-oriented NoSQL database. Stores data as flexible JSON-like documents (BSON). Widely used as a backend for modern web apps — required by Rocket.Chat, LibreChat, and many Node.js applications. Supports replica sets for high availability and oplog tailing.
- **Ports**: 27017 (client connections)
- **Dependencies**: None
- **Volumes**: `/data/db` (database files), `/data/configdb` (config)
- **Config**: `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD` for auth. Replica set mode via `--replSet rs0` command flag (required by Rocket.Chat and many apps that use change streams).
- **Health check**: `mongosh --eval "db.adminCommand('ping')"`
- **Replica set note**: Many apps (Rocket.Chat, Meteor-based apps) require MongoDB in replica set mode even for single-node deployments. This requires a one-shot init container or post-start script running `rs.initiate()`. In Nomad, model this as a `prestart` lifecycle hook or manual init step.
- **Why useful**: Unlocks deployment of MongoDB-dependent apps (Rocket.Chat, LibreChat, many Node.js apps). Provides a document DB option alongside the existing PostgreSQL and MariaDB. Useful for prototyping and apps that store semi-structured data.
- **Why good test**: Single container, but the replica set initialization adds an orchestration challenge not seen in other database deployments. Tests Nomad lifecycle hooks or init patterns. Auth configuration via init env vars is straightforward but different from the Postgres pattern.
- **Tier**: **Easy-Medium** (single container, but replica set init adds orchestration complexity)
- **Project**: <https://github.com/mongodb/mongo>
- **Maintenance**: Official Docker image, actively maintained. Community Edition is free and sufficient.
- **New infra deps**: None (standalone database)
- **Compose reference**:

  ```yaml
  services:
    mongodb:
      image: mongo:7
      command: mongod --replSet rs0 --oplogSize 128
      ports:
        - "27017:27017"
      environment:
        - MONGO_INITDB_ROOT_USERNAME=admin
        - MONGO_INITDB_ROOT_PASSWORD=${MONGO_PASSWORD:-changeme}
      volumes:
        - mongodb_data:/data/db
        - mongodb_config:/data/configdb
    # One-shot init container to initialize replica set
    mongo-init:
      image: mongo:7
      depends_on:
        - mongodb
      command: >
        mongosh --host mongodb --eval "
        try { rs.initiate({ _id: 'rs0', members: [{ _id: 0, host: 'localhost:27017' }] }) }
        catch(e) { if (e.codeName !== 'AlreadyInitialized') throw e }"
      restart: "no"
  ```

### I2: Meilisearch

- **Image**: `getmeili/meilisearch:latest` (v1.16 current)
- **What**: Lightning-fast, typo-tolerant full-text search engine. Single binary (~70MB image), zero external dependencies. RESTful API, instant search-as-you-type. Used by LibreChat, Docmost (optional), and many web apps as a search backend. Lightweight alternative to Elasticsearch.
- **Port**: 7700
- **Dependencies**: None
- **Volumes**: `/meili_data` (indexes and database)
- **Config**: `MEILI_MASTER_KEY` (API key, required in production), `MEILI_ENV=production`, `MEILI_NO_ANALYTICS=true`
- **Health check**: `http://localhost:7700/health`
- **Why useful**: Shared search service for the lab. Can be used by LibreChat, Docmost, or any app needing full-text search. REST API makes it easy to index data from n8n workflows. Much lighter than Elasticsearch (~70MB vs ~700MB image, ~50MB RAM vs ~2GB).
- **Why good test**: Absolute simplest infrastructure service — single container, one volume, two env vars. Comparable to IT-Tools in deployment simplicity but adds a persistent data volume. Good for validating the skill handles search services correctly.
- **Tier**: **Easy** (single container, one volume, minimal config)
- **Project**: <https://github.com/meilisearch/meilisearch>
- **Maintenance**: Very active — 56k GitHub stars, frequent releases. Official Docker image.
- **New infra deps**: None
- **Compose reference**:

  ```yaml
  services:
    meilisearch:
      image: getmeili/meilisearch:latest
      ports:
        - "7700:7700"
      environment:
        - MEILI_MASTER_KEY=${MEILI_MASTER_KEY}
        - MEILI_ENV=production
        - MEILI_NO_ANALYTICS=true
      volumes:
        - meilisearch_data:/meili_data
  ```

### I3: RabbitMQ

- **Image**: `rabbitmq:3-management-alpine` (includes management UI)
- **What**: Enterprise-grade message broker supporting AMQP, MQTT, and STOMP protocols. Management UI provides queue monitoring, message rates, and admin controls. Widely used for task queues (Celery), event-driven architectures, and inter-service messaging. Required by Plane (H2) and commonly used with Paperless-ngx.
- **Ports**: 5672 (AMQP client), 15672 (management UI)
- **Dependencies**: None
- **Volumes**: `/var/lib/rabbitmq` (message persistence, mnesia database)
- **Config**: `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS`, `RABBITMQ_DEFAULT_VHOST`. Optional `rabbitmq.conf` and `definitions.json` for pre-configured exchanges/queues/users.
- **Health check**: `rabbitmq-diagnostics -q ping`
- **Why useful**: Task queue and message broker complementing NATS. NATS excels at lightweight pub/sub; RabbitMQ excels at guaranteed delivery, complex routing (exchanges/bindings), and protocol diversity (AMQP, MQTT for IoT). Unlocks Plane deployment. Useful for Celery-based Python apps.
- **Why good test**: Single container with management UI on a second port — tests multi-port Traefik routing (HTTP UI on 15672, TCP AMQP on 5672). Different deployment pattern from NATS. The `-management-alpine` image variant tests the skill's ability to handle non-default image tags.
- **Tier**: **Easy-Medium** (single container, but two ports with different protocols)
- **Project**: <https://github.com/rabbitmq/rabbitmq-server>
- **Maintenance**: Maintained by Broadcom/VMware. Official Docker image, very stable. AMQP standard.
- **New infra deps**: None
- **Compose reference**:

  ```yaml
  services:
    rabbitmq:
      image: rabbitmq:3-management-alpine
      ports:
        - "5672:5672"
        - "15672:15672"
      environment:
        - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:-admin}
        - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASSWORD:-changeme}
      volumes:
        - rabbitmq_data:/var/lib/rabbitmq
  ```

### I4: Authentik

- **Image**: `ghcr.io/goauthentik/server:latest`
- **What**: Modern open-source identity provider supporting SAML, OAuth2/OIDC, LDAP, SCIM, and RADIUS. Visual flow designer for authentication workflows. Built-in application proxy and outposts for protecting apps without native SSO support. 20k GitHub stars.
- **Ports**: 9000 (HTTP), 9443 (HTTPS)
- **Dependencies**: PostgreSQL (required — uses existing shared instance), Redis (required — uses existing shared instance)
- **Containers**: Server (`command: server` — web UI, API) + Worker (`command: worker` — background tasks, same image)
- **Volumes**: `/media` (branding assets, user uploads), `/templates` (custom email templates)
- **Config**: `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_POSTGRESQL__HOST`, `AUTHENTIK_POSTGRESQL__USER`, `AUTHENTIK_POSTGRESQL__NAME`, `AUTHENTIK_POSTGRESQL__PASSWORD`, `AUTHENTIK_REDIS__HOST`
- **Why useful**: Provides SSO/OIDC for the entire lab. Unlocks Outline (H3) which requires an OIDC provider. Can add SSO to Grafana, pgAdmin, Mattermost, Gitea, and any other app supporting OAuth2/SAML. Centralizes user management. Pairs with Traefik's forward-auth middleware for protecting apps without native auth.
- **Why good test**: Multi-container deployment (server + worker) from the same image with different commands — tests Nomad task group modeling. Uses both existing Postgres and Redis (exercises both `octant-postgres` and `octant-redis` helper skills). The two HTTPS ports and proxy outpost pattern add routing complexity.
- **Tier**: **Medium** (two containers, but uses only existing infrastructure)
- **Project**: <https://github.com/goauthentik/authentik>
- **Maintenance**: Very active — 20k GitHub stars, frequent releases. Official Docker and Helm deployment.
- **New infra deps**: None — uses existing PostgreSQL and Redis
- **Compose reference**:

  ```yaml
  services:
    authentik-server:
      image: ghcr.io/goauthentik/server:latest
      command: server
      ports:
        - "9000:9000"
        - "9443:9443"
      environment:
        - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
        - AUTHENTIK_POSTGRESQL__HOST=postgres.service.consul
        - AUTHENTIK_POSTGRESQL__USER=authentik
        - AUTHENTIK_POSTGRESQL__NAME=authentik
        - AUTHENTIK_POSTGRESQL__PASSWORD=${AUTHENTIK_PG_PASS}
        - AUTHENTIK_REDIS__HOST=redis.service.consul
      volumes:
        - authentik_media:/media
        - authentik_templates:/templates
    authentik-worker:
      image: ghcr.io/goauthentik/server:latest
      command: worker
      environment:
        - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
        - AUTHENTIK_POSTGRESQL__HOST=postgres.service.consul
        - AUTHENTIK_POSTGRESQL__USER=authentik
        - AUTHENTIK_POSTGRESQL__NAME=authentik
        - AUTHENTIK_POSTGRESQL__PASSWORD=${AUTHENTIK_PG_PASS}
        - AUTHENTIK_REDIS__HOST=redis.service.consul
      volumes:
        - authentik_media:/media
        - authentik_templates:/templates
  ```

### I5: MinIO

- **Image**: `minio/minio:latest`
- **What**: High-performance S3-compatible object storage. Single Go binary, production-grade. Provides bucket-based storage with full S3 API compatibility, web console for management, and built-in Prometheus metrics. Used as a local replacement for AWS S3 by dozens of self-hosted apps (Outline, Paperless-ngx, Loki, Tempo, backup tools).
- **Ports**: 9000 (S3 API), 9001 (web console)
- **Dependencies**: None
- **Volumes**: `/data` (object storage — all buckets and objects)
- **Config**: `MINIO_ROOT_USER` (admin username), `MINIO_ROOT_PASSWORD` (admin password, min 8 chars). Command: `server /data --console-address ":9001"`.
- **Health check**: `http://localhost:9000/minio/health/live` (returns 200 OK)
- **Why useful**: Unlocks S3-compatible storage for the entire lab. Required by Outline (H3) for file uploads, useful as a backup target for restic (Phase 2 backup strategy), and provides S3 endpoints for Loki/Tempo long-term storage. The `mc` CLI tool enables bucket policies, lifecycle rules, and event notifications. Eliminates the need for external cloud storage for any S3-dependent app.
- **Why good test**: Two-port deployment (S3 API + web console) similar to RabbitMQ but with different routing patterns — the S3 API needs path-style routing for bucket access, while the console is standard HTTP. Tests Traefik routing for two subdomains from one container (e.g., `minio.lab.shamsway.net` for API, `minio-console.lab.shamsway.net` for UI). The `server` command with `--console-address` flag tests non-default entrypoint handling.
- **Tier**: **Easy-Medium** (single container, but two ports with distinct routing needs)
- **Project**: <https://github.com/minio/minio>
- **Maintenance**: Very active — 51k+ GitHub stars, daily commits. Official Docker image. AGPL v3 license (Community Edition is free for self-hosted use).
- **New infra deps**: None (standalone object storage)
- **Compose reference**:

  ```yaml
  services:
    minio:
      image: minio/minio:latest
      command: server /data --console-address ":9001"
      ports:
        - "9000:9000"
        - "9001:9001"
      environment:
        - MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin}
        - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-changeme}
      volumes:
        - minio_data:/data
  ```

### Infrastructure Layer Summary

| Service         | Prerequisites                  | Tier          | Deployment Pattern                                  |
| --------------- | ------------------------------ | ------------- | --------------------------------------------------- |
| **Meilisearch** | None                           | Easy          | Single container, one volume, minimal config         |
| **MongoDB**     | None                           | Easy-Medium   | Single container + replica set init (lifecycle hook) |
| **RabbitMQ**    | None                           | Easy-Medium   | Single container, multi-port (HTTP UI + AMQP TCP)    |
| **MinIO**       | None                           | Easy-Medium   | Single container, two ports (S3 API + web console)    |
| **Authentik**   | PostgreSQL + Redis (existing)  | Medium        | Multi-container (server + worker), same image         |

**Deployment order**: Meilisearch first (simplest), then MinIO, MongoDB, or RabbitMQ (all Easy-Medium but test different patterns), then Authentik (Medium, unlocks SSO for other apps).

---

## Top Picks

| Tier          | Pick                          | Status      | Rationale                                                                                                                                    |
| ------------- | ----------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **Easy**      | IT-Tools                      | DEPLOYED    | Zero-config baseline. If the skill can't handle this, nothing else will work.                                                                |
| **Easy**      | Linkding                      | DEPLOYED    | Volume mount + env vars on top of IT-Tools.                                                                                                  |
| **Easy**      | Fusion                        | DEPLOYED    | Confirmed consistency across easy tier.                                                                                                      |
| **Medium**    | Docmost                       | DEPLOYED    | Exercises both `octant-postgres` and `octant-redis` helper skills. Clean compose. Lab wiki.                                                  |
| **Medium**    | Linkwarden                    | DEPLOYED    | Postgres-only medium, NEXTAUTH_URL Traefik gotcha validated.                                                                                 |
| **Medium**    | Gitea                         | DEPLOYED    | Git forge with Postgres, SSH routing complexity.                                                                                             |
| **Team Chat** | Rocket.Chat                   | DEPLOYED    | Feature-rich team chat with MongoDB. OpenClaw gateway integration deployed.                                                                  |
| **Knowledge** | NATS                          | DEPLOYED    | Event bus, zero-config baseline.                                                                                                             |
| **Knowledge** | FalkorDB                      | DEPLOYED    | Graph DB, port conflict management validated.                                                                                                |
| **Hard**      | Windmill                      | Pending     | Complex worker architecture, privileged containers, WebSocket routing — but no new infrastructure deps (Postgres only). |
| **Knowledge** | Neo4j + Graphiti              | Pending     | Neo4j needed for Graphiti (official image doesn't support FalkorDB). Terraform ready.                                                        |
| **Team Chat** | Mattermost                    | Pending     | Self-hosted Slack/Discord alternative using existing Postgres. Bot/webhook support.                                                           |
| **Infra**     | MinIO + Meilisearch + RabbitMQ + Authentik | Pending | Four services testing distinct patterns: S3-compatible storage, lightweight search, multi-protocol broker, multi-container SSO.              |

**Deployed**: 10 of 18 candidates (IT-Tools, Linkding, Fusion, NATS, FalkorDB, Docmost, Linkwarden, Gitea, Rocket.Chat + MongoDB).

**Runner-up picks**: Paperless-ngx (medium), Plane (hardest possible test — 6 custom Dockerfile builds).

---

## Deployment Order Recommendation

1. ~~**IT-Tools**~~ — validate basic skill functionality (deployed)
2. ~~**Linkding**~~ — add volume management (deployed)
3. ~~**NATS**~~ — zero-dep messaging, validates easy tier with non-HTTP ports (deployed 2026-03-02)
4. ~~**FalkorDB**~~ — graph DB, tests port conflict management with existing Redis (deployed 2026-03-02)
5. ~~**Fusion**~~ — easy tier with volume, confirmed consistency (deployed)
6. ~~**Docmost**~~ — Postgres + Redis integration, first medium-tier (deployed)
7. ~~**Linkwarden**~~ — Postgres-only medium, NEXTAUTH_URL Traefik gotcha (deployed)
8. ~~**Gitea**~~ — Git forge with Postgres, SSH routing complexity (deployed)
9. ~~**Rocket.Chat**~~ — team chat with MongoDB (new infra dep), deployed with OpenClaw gateway (deployed)
10. **Meilisearch** — easiest remaining infra service: single container, one volume, REST API. Useful as shared search backend.
11. **MinIO** — S3-compatible object storage: two-port routing (API + console), unlocks S3 for backups, Loki/Tempo, and Outline.
12. **Neo4j** — graph DB for Graphiti (required — official Graphiti image doesn't support FalkorDB)
13. **Graphiti** — knowledge graph, tests inter-service deps (Neo4j + LiteLLM). Terraform ready at `terraform/graphiti/`, just needs Neo4j.
14. **MongoDB** — document DB as shared infra, tests replica set init pattern (Nomad lifecycle hooks). Already deployed for Rocket.Chat; may need to be promoted to shared service.
15. **RabbitMQ** — message broker with management UI, tests multi-port routing (HTTP + AMQP TCP). Unlocks Plane.
16. **Mattermost** — team chat with Postgres (existing infra), tests multiple volumes + URL config. Immediately useful for demos and OpenClaw integration.
17. **Authentik** — SSO/OIDC provider, tests multi-container same-image pattern (server + worker). Uses existing Postgres + Redis. Unlocks Outline and SSO for all apps.
18. **Windmill** — full complexity test

This progression builds confidence in the skill incrementally, with each deployment exercising new capabilities on top of the previous ones. Infrastructure services are interleaved at natural complexity breakpoints — Meilisearch (Easy) slots in with other simple services, MongoDB and RabbitMQ (Easy-Medium) test new patterns before Medium-tier apps, and Authentik (Medium) unlocks SSO before tackling harder deployments.
