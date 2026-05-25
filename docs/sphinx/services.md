# Service Catalog

## Monitoring

| Service | Purpose | URL | Storage | Image |
|---------|---------|-----|---------|-------|
| Prometheus | Metrics collection and alerting | [prometheus.lab.example.com](https://prometheus.lab.example.com) | CSI RBD | `prom/prometheus:v3.9.1` |
| Grafana | Dashboards and visualization | [grafana.lab.example.com](https://grafana.lab.example.com) | CephFS | `grafana/grafana:12.3.3` |
| Loki | Log aggregation | [loki.lab.example.com](https://loki.lab.example.com) | CSI RBD | `grafana/loki:3.6.6` |
| Tempo | Distributed tracing | — | CephFS | `grafana/tempo:2.8.2` |
| Alertmanager | Alert routing and notification | — | CephFS | `prom/alertmanager:v0.28.1` |
| Alloy | Telemetry collector (metrics, logs, traces) | — | — | `grafana/alloy:v1.8.3` |
| Gatus | Endpoint health monitoring | [gatus.lab.example.com](https://gatus.lab.example.com) | CephFS | `twinproduction/gatus:v5.34.0` |
| Uptime Kuma | Uptime monitoring and status page | [uptimekuma.lab.example.com](https://uptimekuma.lab.example.com) | CephFS | `louislam/uptime-kuma:2.1.3` |

## Databases

| Service | Purpose | URL | Storage | Image |
|---------|---------|-----|---------|-------|
| PostgreSQL | Primary relational database | — | CSI RBD | `postgres:16.2` |
| MariaDB | Secondary relational database | — | CSI RBD | `mariadb:10.11` |
| MongoDB | Document database (3-node replica set) | — | CSI RBD (×3) | `mongo:8` |
| Neo4j | Graph database | [neo4j.lab.example.com](https://neo4j.lab.example.com) | CSI RBD | `neo4j:5-community` |
| Qdrant | Vector database | — | CSI RBD | `qdrant/qdrant:v1.12.5-unprivileged` |
| Redis | In-memory cache / message broker | — | CephFS | `redis:7` |

## AI / ML

| Service | Purpose | URL | Storage | Image |
|---------|---------|-----|---------|-------|
| LiteLLM | LLM API proxy | — | — | `ghcr.io/berriai/litellm:main-latest` |
| Open WebUI | Chat interface for LLMs | [open-webui.lab.example.com](https://open-webui.lab.example.com) | CephFS | `ghcr.io/open-webui/open-webui:main` |
| Phoenix | LLM observability and tracing | [phoenix.lab.example.com](https://phoenix.lab.example.com) | CephFS | `arizephoenix/phoenix:13.0.3-nonroot` |
| SearXNG | Privacy-respecting meta search | [searxng.lab.example.com](https://searxng.lab.example.com) | CephFS | `searxng/searxng:latest` |
| Graphiti | Temporal knowledge graph | — | — | Custom build |
| OpenClaw | Agent gateway (LLM agents via Rocket.Chat) | [openclaw.lab.example.com](https://openclaw.lab.example.com) | CephFS | `openclaw/openclaw:latest` |

## Applications

| Service | Purpose | URL | Storage | Image |
|---------|---------|-----|---------|-------|
| n8n | Workflow automation | [n8n.lab.example.com](https://n8n.lab.example.com) | CephFS | `n8nio/n8n:1.122.5` |
| Gitea | Git hosting | [gitea.lab.example.com](https://gitea.lab.example.com) | CephFS | `gitea/gitea:latest` |
| Excalidraw | Collaborative whiteboard | [excalidraw.lab.example.com](https://excalidraw.lab.example.com) | — | `excalidraw/excalidraw:latest` |
| Homepage | Dashboard / service launcher | [homepage.lab.example.com](https://homepage.lab.example.com) | CephFS | `gethomepage/homepage:latest` |
| pgAdmin | PostgreSQL management UI | [pgadmin.lab.example.com](https://pgadmin.lab.example.com) | CephFS | `dpage/pgadmin4:latest` |
| Linkding | Bookmark manager | [linkding.lab.example.com](https://linkding.lab.example.com) | CephFS | `sissbruecker/linkding:latest` |
| Linkwarden | Bookmark archive | [linkwarden.lab.example.com](https://linkwarden.lab.example.com) | CephFS | `ghcr.io/linkwarden/linkwarden:latest` |
| IT-Tools | Developer utilities | [it-tools.lab.example.com](https://it-tools.lab.example.com) | — | `corentinth/it-tools:latest` |
| PlantUML | Diagram rendering | [plantuml.lab.example.com](https://plantuml.lab.example.com) | — | `plantuml/plantuml-server:latest` |
| ntfy | Push notifications | [ntfy.lab.example.com](https://ntfy.lab.example.com) | CephFS | `binwiederhier/ntfy:latest` |

## Infrastructure

| Service | Purpose | URL | Storage | Image |
|---------|---------|-----|---------|-------|
| Traefik | Reverse proxy and TLS termination | [traefik.lab.example.com](https://traefik.lab.example.com) | CephFS | `traefik:v3.0.2` |
| Nginx | Static file hosting | [web.lab.example.com](https://web.lab.example.com) | CephFS | `nginxinc/nginx-unprivileged:1.25.4` |

## Backup Jobs

| Job | Type | Schedule | Purpose | Storage-aware |
|-----|------|----------|---------|---------------|
| postgres-backup | Batch (periodic) | Daily 04:30 | `pg_dumpall` to `/mnt/services/backups/postgres/` | Yes — runs inside container, works with both CephFS and CSI |
| mariadb-backup | Batch (periodic) | Daily 04:00 | `mariadb-dump` to `/mnt/services/backups/mariadb/` | Yes — runs inside container |
| restic-backup | Batch (periodic) | Daily | Restic snapshot of `/mnt/services/` | CephFS only — does not capture CSI RBD data |

## Notes

- All URLs use `https://<service>.lab.example.com` via Traefik
- Internal service discovery uses Consul DNS: `<service>.service.consul`
- Services without a URL listed are internal-only (accessed via Consul DNS)
- **Storage column:** `CSI RBD` = dedicated Ceph block device (Docker, root agent), `CephFS` = shared filesystem (Podman, rootless agent), `—` = stateless
- Database dump jobs (`nomad alloc exec`) work regardless of storage backend — they run inside the container where the volume is already mounted
- Restic only backs up `/mnt/services/` (CephFS). CSI RBD data is protected by database dump jobs, not file-level backups.
