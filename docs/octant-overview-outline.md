# Octant Lab
## A Private Cloud Platform for AI Demos and Enterprise Prototyping

# Why Octant?

## The Problem
- Building AI demos requires real infrastructure: GPUs, databases, orchestration, observability
- Public cloud demos are expensive, ephemeral, and constrained by vendor policies
- Docker Compose doesn't scale; Kubernetes is overkill for demo environments
- Teams need a platform that's always-on, self-service, and purpose-built for AI workloads

## What Octant Delivers
- **Private cloud platform** — 3-node cluster with 50+ services, GPU inference, and full observability
- **Deploy anything in minutes** — Template-based workflow turns any Docker image into a managed service
- **AI-native infrastructure** — LLM routing, vector databases, agent orchestration, and ML notebooks built in
- **Production patterns at lab scale** — Same tools enterprises use (Nomad, Consul, Terraform) without the complexity

# Architecture

## Platform Stack
- **Compute**: 3 KVM virtual machines (Debian 12) on a dedicated hypervisor
- **Orchestration**: HashiCorp Nomad schedules and manages all workloads
- **Service Discovery**: HashiCorp Consul provides DNS, health checks, and KV storage
- **Container Runtime**: Rootless Podman (secure by default, rootful available when needed)
- **Storage**: CephFS distributed filesystem shared across all nodes
- **Ingress**: Traefik reverse proxy with automatic TLS via Let's Encrypt
- **Secrets**: 1Password integration with Nomad variables

## How Requests Flow
- Internet DNS resolves to HAProxy on the hypervisor
- HAProxy load-balances across Traefik instances on all 3 nodes
- Traefik auto-discovers services from Consul Catalog and routes by hostname
- Services run as Podman containers scheduled by Nomad
- Persistent data lives on CephFS, available from any node

## Infrastructure as Code
- **Ansible** (27 roles): Provisions VMs, configures cluster, manages storage
- **Terraform** (58 modules): Deploys every service declaratively
- **Packer**: Builds golden VM images for consistent provisioning
- **Makefile**: 50+ targets for common operations
  - `make fresh-deploy` — Full cluster from scratch
  - `make deploy` — Incremental updates
  - `make health-check` — Cluster validation

# AI and LLM Capabilities

## GPU Inference Pipeline
- **AMD MI300X** on the hypervisor provides 1.5TB VRAM for large model serving
- **vLLM** serves multiple models simultaneously
  - DeepSeek V3.2 (671B parameters, Mixture of Experts)
  - Qwen 3.5 (397B parameters)
  - GLM-5-FP8
- **LiteLLM** provides a unified OpenAI-compatible API gateway
  - Routes to local vLLM or external providers (OpenAI, Anthropic, Groq)
  - All cluster services connect via `litellm.service.consul:4000`

## AI Agent Platforms
- **BastionClaw**: Container-native agent orchestrator
  - Agents run as managed Podman containers
  - Multi-agent coordination via Telegram
  - Spawns child containers for agentic workloads
- **OpenClaw Gateway**: AI crew platform on Discord
  - Hub agent (Scotty) routes requests to specialized agents
  - Integrates with LiteLLM for local model access

## LLM Observability
- **Phoenix**: Traces LLM calls with latency, token usage, and cost metrics
- **LangFuse**: Production-grade LLM monitoring and evaluation
- Both integrate with LiteLLM for automatic instrumentation

## ML and Data Science Tools
- **Jupyter Notebooks**: PyTorch environment for prototyping and experimentation
- **Open-WebUI**: Chat interface for interacting with any model through LiteLLM

# Vector and Graph Databases

## Embedding and Semantic Search
- **Qdrant**: High-performance vector database for production RAG pipelines
- **ChromaDB**: Lightweight embedding store for rapid prototyping
- **Weaviate**: Vector database with GraphQL API and hybrid search

## Knowledge Graphs
- **Neo4j**: Enterprise graph database for relationship modeling
- **FalkorDB**: Redis-compatible graph DB for low-latency graph queries
- **Graphiti**: Graph visualization and temporal knowledge graphs

## What You Can Build
- Retrieval-Augmented Generation (RAG) pipelines with any vector DB
- Knowledge graph-powered AI agents
- Semantic search over enterprise document collections
- Multi-modal embedding pipelines with GPU acceleration

# Deploying a Demo

## Five-Step Workflow
- **Copy** the service template: `cp -r terraform/template terraform/my-demo`
- **Configure** the Nomad job spec: image, ports, environment variables, Traefik routing
- **Add storage** (if needed): Define volumes in `inventory/groups.yml`, run `make deploy-volumes`
- **Deploy**: `cd terraform/my-demo && terraform init && terraform apply`
- **Verify**: Service appears in Nomad UI, health checks pass in Consul, URL is live

## What You Get Automatically
- Consul DNS registration (`my-demo.service.consul`)
- Traefik HTTPS routing (`my-demo.lab.shamsway.net`)
- Health monitoring in Gatus and Uptime Kuma
- Logs in Loki, metrics in Prometheus, traces in Tempo
- CephFS persistence that survives node failures
- Automated backups via Restic

## Docker-to-Nomad Converter
- Claude-powered Streamlit app converts Docker Compose files to Nomad job specs
- Handles volume mapping, port configuration, environment variables, and Traefik tags
- Reduces migration effort from hours to minutes

# Observability Stack

## Full-Stack Monitoring
- **Prometheus** scrapes metrics via Consul service discovery (no manual config)
- **Grafana** provides dashboards for infrastructure, containers, and applications
- **Loki** aggregates logs from all containers via Alloy
- **Tempo** collects distributed traces via OpenTelemetry
- **Alertmanager** routes notifications to Slack, Discord, email, or ntfy
- **Gatus** monitors 11+ endpoints with uptime history
- **Uptime Kuma** provides external monitoring and public status pages

## Why This Matters for Demos
- Show real-time metrics during live demos
- Correlate logs, metrics, and traces in a single pane of glass
- Demonstrate enterprise-grade observability alongside AI workloads
- Every service is monitored from the moment it deploys

# Platform Services

## Shared Infrastructure
- **PostgreSQL 16**: Primary relational database (15+ services connected)
- **MariaDB 10.11**: Secondary relational database
- **Redis**: In-memory cache and session store (DB 0-15 allocation)
- **NATS and MQTT**: Message brokers for event-driven architectures
- **MinIO**: S3-compatible object storage

## Developer and Productivity Tools
- **Gitea**: Self-hosted Git for demo source code
- **n8n**: Visual workflow automation (connects 200+ services)
- **Excalidraw**: Collaborative whiteboard for architecture diagrams
- **PlantUML**: Programmatic diagram generation
- **IT-Tools**: Swiss army knife of developer utilities
- **Homepage**: Service dashboard and launcher

## Networking and Operations
- **Traefik**: Automatic TLS, routing, and load balancing
- **Tailscale**: Zero-trust mesh networking for remote access
- **Cloudflare**: DNS management and external access

# Use Cases for Technical Marketing

## Live Demo Scenarios
- Deploy a customer-specific AI demo in minutes, tear it down after
- Run side-by-side model comparisons (DeepSeek vs Qwen vs GPT) through LiteLLM
- Show RAG pipelines with real vector databases and local GPU inference
- Demonstrate enterprise observability for AI workloads (Phoenix, LangFuse)

## Proof-of-Concept Hosting
- Stand up persistent demos that customers can revisit
- Each demo gets its own URL, storage, and monitoring
- CephFS persistence means demos survive node reboots and maintenance

## Internal Prototyping
- Test new AI models on MI300X before recommending to customers
- Build agent architectures with BastionClaw or OpenClaw
- Prototype integrations with n8n workflow automation
- Experiment with graph databases for knowledge-powered AI

## Team Enablement
- Self-service deployment: anyone can deploy from the template
- Comprehensive docs and runbooks reduce onboarding friction
- State capture playbook generates point-in-time cluster snapshots for auditing

# Security and Operations

## Security by Default
- **Rootless Podman** for all standard workloads (50+ services)
- **1Password** integration for secrets management (no plaintext credentials)
- **TLS everywhere** via Let's Encrypt with Cloudflare DNS-01 challenges
- **Constraint-based scheduling** isolates privileged workloads

## Backup and Recovery
- **Daily database backups**: PostgreSQL and MariaDB dumps with 30-day retention
- **Restic snapshots**: Incremental, deduplicated backups of all service volumes
- **Consul and Nomad snapshots**: Cluster state preserved for disaster recovery
- **Full rebuild capability**: `make rebuild-clean` restores the entire cluster from scratch

## Operational Excellence
- Rolling node maintenance with zero-downtime procedures
- Health check playbooks validate cluster state
- State capture generates machine-readable cluster snapshots
- 50+ Makefile targets for routine operations

# Getting Started

## What You Need
- A hypervisor with KVM support (bare metal or nested virtualization)
- 1Password account for secrets management
- Cloudflare account for DNS (optional, sslip.io works without it)
- Clone the repo, copy `.envrc.example`, and run `make fresh-deploy`

## First Demo in Under an Hour
- Cluster deploys from scratch with `make fresh-deploy`
- 50+ services come up automatically
- GPU inference available immediately via LiteLLM
- Pick a Docker image, copy the template, deploy your first demo

## Resources
- Full documentation published via Sphinx at `docs.lab.shamsway.net`
- Demo scripts with step-by-step walkthroughs
- Design documents for every major infrastructure decision
- Claude Code plugins for assisted deployment workflows
