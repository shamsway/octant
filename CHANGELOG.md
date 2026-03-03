# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

#### VM Deployment Pipeline
- KVM-based virtual machine provisioning with `vm_provision` and `vm_storage` Ansible roles
- Base image builder playbook (`00-build-base-image.yml`) with Ceph, HashiCorp, and Podman packages
- Full deployment orchestrator (`site.yml`) with numbered phase playbooks (provision, ceph, services, health-check, teardown)
- VM lifecycle Makefile targets (`deploy-vm`, `teardown`, `rebuild`)
- DHCP reservations with fixed MAC addresses for deterministic VM networking
- Hypervisor inventory (`inventory/hypervisors.yml`) for KVM host management

#### Storage
- Ceph role for automated cephadm bootstrap, OSD creation, CephFS filesystem, and cluster-wide mounting
- Volumes role for declarative CephFS directory creation from inventory
- Container storage role for Podman storage configuration

#### Networking & Ingress
- HAProxy role for hypervisor-level load balancing across VM nodes
- DNS tier support with sslip.io default and optional Cloudflare DNS
- Cloudflare DNS terraform module (`dns-lab/`) for wildcard records
- Traefik HTTPS ingress with 1Password-sourced Cloudflare credentials

#### Service Deployments (new Terraform modules)
- **Observability:** Prometheus (with Consul auto-discovery), Loki, Tempo, Alertmanager, Alloy, Grafana (with datasource provisioning), Gatus
- **Productivity:** Homepage (with service dashboard config), IT-Tools, Excalidraw, Linkding, Linkwarden, Fusion (RSS)
- **AI/ML:** Open-WebUI, Phoenix (LLM observability), Graphiti (temporal knowledge graph), ChromaDB, Qdrant, Weaviate
- **Infrastructure:** NATS (with JetStream), Neo4j, MariaDB, MQTT, Nginx
- **Automation:** n8n, Ntfy, SearXNG, Gitea
- **Management:** PgAdmin, MariaDB-backup, Postgres-backup
- **Networking:** Unifi controller, Uptimekuma
- **Backup:** Restic with Consul/Nomad snapshots and local CephFS repo

#### Secrets Management
- 1Password integration via `secrets` role with `.env` fallback
- `seed-onepassword` role for automated credential creation in 1Password vault
- Secret generation script (`scripts/generate-secrets.sh`)
- Standardized secrets naming convention (`service_<name>` pattern)

#### Monitoring & Metrics
- Node-exporter role with Consul service registration
- Podman-exporter role with rootless and rootful support
- Prometheus Consul-based service auto-discovery (replaces individual scrape configs)

#### Operations
- Health-check playbook validating Consul, Nomad, and Ceph across all nodes
- Lab state capture playbook with JSON-to-markdown conversion
- Service destroy playbook for clean teardown
- Pre-commit hooks for secrets scanning (gitleaks), YAML/Ansible/shell/markdown linting
- Design and implementation plan document templates

### Changed

- Renamed `homelab.yml` to `octant.yml` (homelab-to-octant rebrand)
- Changed `/opt/homelab/` paths to `/opt/octant/` across all roles and templates
- Updated core roles (consul, nomad, requirements, podman, install-hashi) for VM deployment compatibility
- Switched from `ansible_eth0` to `ansible_default_ipv4` in network templates
- Made Tailscale references conditional via `tailscale_enabled` variable
- Simplified LiteLLM to require only OpenAI API key
- Added LiteLLM local model support and Arize Phoenix observability integration
- Updated Terraform template to use `templatefile()` (replacing deprecated `data.template_file`)
- Templatized `traefik.toml` to remove hardcoded values
- Switched Restic backup repo from remote to local CephFS path
- Upgraded VM resources to 24 GB RAM / 8 vCPUs per node

### Removed

- Removed `terraform/op/` (1Password group deployment, replaced by seed-onepassword role)

### Fixed

- TLS certificate generation and distribution for Consul and Nomad agents
- Non-root agent TLS cert permissions
- Nomad startup failures from incorrect port references
- Ceph deployment prerequisites and ceph.conf distribution
- Variable escaping issues in Nomad HCL templates
- Consul/Nomad service template conditional rendering
- DNS resolution for services using Consul DNS servers
- Homepage `HOMEPAGE_ALLOWED_HOSTS` validation error
- Terraform deployment issues for controller-local execution
