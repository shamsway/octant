# Octant Agent Skills Ecosystem Design

## Overview

A platform-agnostic collection of AgentSkill-spec skills that enable AI agents to act as SREs, coding agents, planners, and documentation writers for the Octant VM deployment environment. Designed for OpenClaw, BastionClaw, Claude Code, or any AgentSkill-compatible runtime.

## Architecture

**Two-tier planner + doers** model with four skill tiers:

- **Tier 0 — Meta agents**: Task decomposition (planner) and self-evolution (skill developer)
- **Tier 1 — Domain leads**: Coordinate specialists within observability and AI platform domains
- **Tier 2 — Specialists**: Deep service-specific knowledge and operations
- **Tier 3 — Event-driven**: Webhook handling, runbook execution, documentation generation

**Scope**: AI/LLM stack + monitoring stack with basic ops/troubleshooting. Designed for future extensibility (e.g., Alertmanager webhooks triggering agent workflows).

## Skill Inventory (20 Skills)

### Tier 0 — Meta Agents

| Skill | Purpose |
|-------|---------|
| `octant-planner` | Task decomposition engine. Receives user requests, breaks them into ordered subtasks with dependencies, routes each to the appropriate domain lead or specialist, dispatches (parallel where independent), and synthesizes results into a unified response. |
| `octant-skill-developer` | Creates, validates, and deploys new AgentSkill-spec skills. Researches service documentation, drafts SKILL.md with frontmatter, validates with `skills-ref`, and requires Lobster-style approval gates at design, implementation, and deployment checkpoints. Can also create new agent configurations and update existing skills. |

### Tier 1 — Domain Leads

| Skill | Purpose |
|-------|---------|
| `octant-observability-lead` | Coordinates monitoring, logging, tracing, and alerting across the Octant stack. Routes to Prometheus (metrics), Grafana (dashboards), Loki (logs), Tempo (traces), Alertmanager (alert routing), Alloy (telemetry collection), Gatus/Uptime Kuma (health checks). Understands how these systems interconnect and guides cross-service correlation. |
| `octant-ai-platform-lead` | Coordinates the AI/LLM services stack. Routes to LiteLLM (model proxy), Langfuse (LLM observability), vector databases (Qdrant/Weaviate/ChromaDB), Open WebUI (chat interface), and OpenClaw Gateway (agent runtime). Understands model deployment pipelines and inference optimization. |

### Tier 2 — Specialists (Observability Domain)

| Skill | Purpose |
|-------|---------|
| `octant-prometheus` | PromQL queries, recording rules, alert rules, scrape target configuration, federation, storage management. Covers the Prometheus v3.x deployment on Nomad. |
| `octant-grafana` | Dashboard creation (JSON model and UI), data source configuration, alert contact points, notification policies, provisioning via config files, dashboard-as-code patterns. |
| `octant-loki` | LogQL queries, log pipeline configuration, Alloy/Promtail shipper setup, retention policies, multi-tenant configuration, log-to-metric conversions. |
| `octant-alertmanager` | Alert routing trees, receiver configuration (ntfy, email, webhook), silences, inhibition rules, webhook integration for event-driven automation. |
| `octant-tempo` | TraceQL queries, trace-to-logs/metrics correlation, sampling strategies, Tempo storage configuration, span search and filtering. |

### Tier 2 — Specialists (AI Platform Domain)

| Skill | Purpose |
|-------|---------|
| `octant-litellm` | LiteLLM proxy configuration, model routing, API key management, rate limiting, fallback chains, cost tracking, OpenAI-compatible endpoint management. |
| `octant-langfuse` | LLM trace ingestion, prompt management, evaluation scoring, dataset creation, integration with LiteLLM callbacks, cost analysis. |
| `octant-vector-db` | Qdrant/Weaviate/ChromaDB collection management, embedding pipelines, similarity search, index optimization, backup/restore. Covers all three vector DBs deployed in the environment. |
| `octant-openwebui` | Open WebUI configuration, model connections (LiteLLM/Ollama), RAG pipeline setup, user management, custom model presets. |

### Tier 2 — Specialists (Ops/Infrastructure)

| Skill | Purpose |
|-------|---------|
| `octant-nomad-consul` | Nomad job management (submit, stop, inspect, alloc logs), Consul service discovery, health checks, KV store operations, service mesh configuration. Foundation skill for all deployed services. |
| `octant-traefik` | Ingress routing rules, TLS/Let's Encrypt configuration, middleware (auth, rate limiting, headers), Consul Catalog provider, dashboard access, troubleshooting 502/503 errors. |
| `octant-database-ops` | PostgreSQL and MariaDB administration: queries, backups, restores, replication monitoring, connection troubleshooting, Redis cache operations, pgAdmin usage. |
| `octant-general-ops` | Linux system troubleshooting, DNS management, NFS mounts, backup verification, disk/memory/CPU diagnostics, container runtime debugging, SSH access patterns. Catch-all for ops tasks not covered by specialists. |

### Tier 3 — Event-Driven / Extensibility

| Skill | Purpose |
|-------|---------|
| `octant-webhook-handler` | Processes incoming webhooks from Alertmanager, Grafana, N8N, or other services. Parses alert payloads, determines severity and affected service, triggers appropriate specialist agent or runbook. Designed for event-driven automation. |
| `octant-runbook-executor` | Executes pre-defined operational runbooks for common incidents (high CPU, disk full, service crash, certificate expiry, model endpoint down). Each runbook is a structured procedure with diagnostic steps, remediation actions, and escalation criteria. |
| `octant-documentation-writer` | Generates and maintains operational documentation: runbooks, architecture diagrams (PlantUML), service dependency maps, incident postmortems, and configuration reference docs. Can query running services for current state. |

## Skill Architecture

### Directory Structure

```
skills/
├── octant-planner/
│   ├── SKILL.md
│   └── references/
│       ├── skill-registry.md           # Complete list of available specialists
│       └── decomposition-patterns.md   # Common task→subtask patterns
├── octant-skill-developer/
│   ├── SKILL.md
│   ├── references/
│   │   ├── agentskill-spec.md          # AgentSkill spec quick reference
│   │   ├── skill-templates.md          # Starter templates per skill type
│   │   └── validation-checklist.md     # Pre-deployment checks
│   └── assets/
│       └── skill-template/             # Scaffold directory structure
├── octant-observability-lead/
│   ├── SKILL.md
│   └── references/
│       ├── service-map.md              # How monitoring services connect
│       └── common-workflows.md         # Alert→diagnose→resolve patterns
├── octant-<specialist>/
│   ├── SKILL.md
│   ├── references/
│   │   ├── <query-language>-reference.md
│   │   ├── configuration.md
│   │   └── troubleshooting.md
│   └── scripts/                        # Optional helper scripts
│       └── *.sh
├── octant-webhook-handler/
│   ├── SKILL.md
│   └── references/
│       └── payload-schemas.md          # Alertmanager, Grafana webhook formats
├── octant-runbook-executor/
│   ├── SKILL.md
│   └── references/
│       └── runbooks/
│           ├── service-down.md
│           ├── high-disk-usage.md
│           ├── certificate-expiry.md
│           ├── model-endpoint-down.md
│           ├── scrape-target-missing.md
│           └── database-connection-pool.md
└── octant-documentation-writer/
    ├── SKILL.md
    └── references/
        └── templates/                  # Doc templates (runbook, postmortem, etc.)
```

### Naming Convention

All skills prefixed with `octant-` to namespace and avoid collisions with existing plugins or ClawdHub skills.

### SKILL.md Template Pattern

```yaml
---
name: octant-<service>
description: >
  <Action verbs describing capabilities>.
  Use when <activation triggers>.
  Covers <specific scope>.
---
```

```markdown
You are an expert <domain> engineer managing <service> in the Octant
homelab environment. Help the user <primary actions>. Provide specific
<commands/configs/queries> from the reference below.

For <adjacent concern>, route to the `octant-<other-skill>` skill.

## Environment Context

- Deployment: Nomad job on Consul-managed infrastructure
- Service address: <service>.service.consul
- Version: <version>
- Traefik ingress: <url pattern>

---

# <Service Name>

## Key Operations
...

## Configuration
...

## Troubleshooting
...
```

### Token Budget Targets

| Tier | SKILL.md body | References total |
|------|--------------|-----------------|
| Tier 0 (meta) | ~3000 tokens | ~5000 tokens |
| Tier 1 (leads) | ~2000 tokens | ~3000 tokens |
| Tier 2 (specialists) | ~4000 tokens | ~8000 tokens |
| Tier 3 (event-driven) | ~2500 tokens | ~5000 tokens |

Discovery cost at startup: ~20 skills x ~75 tokens = ~1500 tokens total.

### Inter-Skill Routing

- **Planner** routes to domain leads by category
- **Domain leads** route to specialists by service name
- **Specialists** route back to domain lead for cross-service concerns, or to `octant-general-ops` for infrastructure issues
- **Event-driven skills** route to specialists for remediation, back to planner for complex multi-step incidents

## Planner Agent Design

### Task Decomposition Flow

```
User Request → Classify (domain) → Decompose (subtasks) → Route (assign) → Execute (dispatch) → Synthesize (respond)
```

### Classification Categories

| Domain | Trigger patterns | Routes to |
|--------|-----------------|-----------|
| Observability | metrics, alerts, dashboards, logs, traces, monitoring, SLO | `octant-observability-lead` |
| AI Platform | models, inference, LLM, embeddings, RAG, prompts, tokens | `octant-ai-platform-lead` |
| Infrastructure | Nomad, Consul, Traefik, DNS, containers, ingress | Direct to specialist |
| Database | queries, backups, replication, tables, connections | `octant-database-ops` |
| General ops | disk, CPU, memory, SSH, NFS, certificates | `octant-general-ops` |
| Cross-domain | "why is X slow", incident response, capacity planning | Decompose across leads |
| Meta | "create a new skill", "add an agent for X" | `octant-skill-developer` |

### Cross-Domain Example

User: *"Grafana is showing gaps in my LiteLLM request metrics"*

Planner decomposes:
1. `octant-grafana` — check dashboard data source config, query time range
2. `octant-prometheus` — verify LiteLLM scrape target is up, check for dropped samples
3. `octant-litellm` — verify metrics endpoint is enabled, check `/metrics` output
4. `octant-observability-lead` — correlate findings, suggest fix

## Skill Developer Agent Design

### Workflow with Approval Gates

```
[Gate 0: Accept] → Confirm scope, check for duplicates
    ↓
[Research Phase] → Autonomous
    ├── Web search for official docs, CLI references, API specs
    ├── Inspect running service (Consul catalog, Nomad job, Traefik routes)
    ├── Check existing skills for overlap or routing conflicts
    └── Identify integration points with existing skills
    ↓
[Gate 1: Design Approval] ← Human reviews
    ├── Proposed skill name, description, tier placement
    ├── Section outline for SKILL.md
    ├── Reference docs plan
    ├── Routing: which skills route TO this one, which it routes TO
    └── Estimated token budget
    ↓
[Implementation Phase] → Autonomous
    ├── Write SKILL.md with frontmatter and preamble
    ├── Write reference docs
    ├── Add any helper scripts
    └── Run skills-ref validate
    ↓
[Gate 2: Implementation Review] ← Human reviews
    ├── Full SKILL.md content
    ├── Validation output (must pass)
    ├── Token count check (within budget?)
    └── Test activation queries
    ↓
[Deployment Phase] → Autonomous
    ├── Update planner's skill-registry.md
    ├── Update relevant domain lead's routing table
    └── Update octant-planner if new domain added
    ↓
[Gate 3: Deployment Approval] ← Human reviews final diff
```

### Guardrails

- Cannot modify Tier 0 skills (planner, itself) without explicit user request
- Cannot delete skills — only propose deprecation for human decision
- Cannot change inter-skill routing without Gate 3 approval
- All generated skills must pass `skills-ref validate` before Gate 2

### Self-Improvement Loop

The skill developer can update existing skills when it detects:
- Service version changes (Nomad job shows new image tag)
- New CLI commands or API endpoints discovered during research
- User frequently asks questions a skill can't answer (gap detection)
- Cross-skill routing is broken or ambiguous

Same approval gates apply to updates.

## Event-Driven Extensibility (Tier 3)

### Webhook Handler Architecture

```
Alertmanager ──┐
Grafana ───────┤                    ┌─────────────────────────┐
N8N ───────────┼── webhook POST ──→ │ octant-webhook-handler  │
Uptime Kuma ───┤                    │  ├── Parse payload       │
Custom ────────┘                    │  ├── Classify severity   │
                                    │  ├── Identify service    │
                                    │  └── Route to:           │
                                    │     ├── runbook-executor  │
                                    │     └── planner           │
                                    └─────────────────────────┘
```

### Event Classification

| Severity | Source Example | Action |
|----------|--------------|--------|
| Critical | Alertmanager: `service_down` | Immediate runbook execution, notify human |
| Warning | Prometheus: `high_memory` | Diagnostic runbook, report findings |
| Info | Grafana: `SLO budget burn` | Log insight, suggest proactive action |
| Custom | N8N: workflow trigger | Route to planner for task decomposition |

### Runbook Structure

Each runbook in `references/runbooks/` follows:

```markdown
## Trigger
When: <alert name or condition>

## Diagnostics
1. Check X → expected: Y
2. Query Z → look for: W

## Remediation
1. If diagnostic 1 failed → do A
2. If diagnostic 2 failed → do B

## Escalation
If remediation fails → notify human with diagnostic output
```

### Initial Runbooks

- `service-down.md` — Check Nomad alloc, restart, escalate
- `high-disk-usage.md` — Identify consumers, clean logs, expand volume
- `certificate-expiry.md` — Renew via Traefik/Let's Encrypt, verify
- `model-endpoint-down.md` — Check LiteLLM, verify vLLM, failover
- `scrape-target-missing.md` — Consul service check, Prometheus config
- `database-connection-pool.md` — PG/MariaDB connection diagnostics

### Learning Loop

The system improves over time:

1. Webhook triggers agent → agent resolves (or escalates)
2. Documentation writer captures the pattern as a new runbook
3. Skill developer proposes adding it (with approval gates)
4. Runbook executor can handle it automatically next time

## Octant Environment Context

All skills target the Octant VM deployment running on Nomad/Consul with these key services:

**Monitoring**: Prometheus v3.9.1, Grafana 12.3.3, Alertmanager v0.28.1, Loki 3.6.6, Tempo 2.8.2, Alloy v1.8.3, Gatus v5.34.0, Uptime Kuma 2.1.3

**AI/LLM**: LiteLLM (ghcr.io/berriai/litellm-database:main-stable), Open WebUI v0.5.16, Langfuse (latest), OpenClaw Gateway (custom image)

**Vector DBs**: Qdrant v1.12.5, Weaviate, ChromaDB

**Infrastructure**: Traefik v3.0.2, Consul, Nomad, PostgreSQL 16.2, MariaDB 10.11, Redis 7.2.4

**Utilities**: N8N 1.122.5, Ntfy, SearXNG, PlantUML, Excalidraw, Homepage
