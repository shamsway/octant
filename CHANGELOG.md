# Changelog

All notable changes to Octant are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and dates are
ISO‑8601 (YYYY‑MM‑DD).

## [Unreleased]

### Added

**VM-based cluster (default deployment path)**
- Packer‑style golden base image on Debian 13 (Trixie) cloud image
- Playbooks `00..12` for the full VM lifecycle: build base image,
  provision VMs, deploy Ceph, deploy services, health-check, deploy
  volumes, destroy, capture state, graceful shutdown, cold snapshot,
  cluster start, hypervisor join/remove
- `inventory/groups.yml` as the single source of truth for nodes,
  volumes, and resource allocations
- Ansible roles for `vm_provision`, `vm_storage`, `container-storage`,
  `apply-terraform`, `node-exporter`, `podman-exporter`, plus a major
  overhaul of `consul-*`, `nomad-*`, `podman-root`, `podman-rootless`,
  `install-hashi`, `requirements`, `secrets`, `seed-onepassword`, `ceph`,
  `restic`, `docker`, `haproxy`
- Repo plumbing: `ansible.cfg`, `.ansible-lint`, `.yamllint.yml`,
  `.markdownlint.json`, `.pre-commit-config.yaml`, `.gitleaks.toml`,
  `CLAUDE.md`

**Hypervisor + GPU workloads**
- Playbooks to join/remove a GPU‑bearing hypervisor as a Nomad client
  with explicit `server_join`, bind‑addr scoping, and handler flushing
- `terraform/gpu-rocm-test/`, `terraform/gpu-pytorch-test/` — ROCm and
  PyTorch smoke‑test workloads against `nomad-device-amdgpu`
- `terraform/instinct-dash/` — AMD GPU dashboard (Docker driver)
- `terraform/vllm-gemma4-31b/` — vLLM serving Gemma‑4 31B

**Ceph CSI block storage**
- `terraform/ceph-csi/` — controller + node plugin Nomad jobs (node
  plugin uses host networking so the kernel RBD client can reach Ceph
  mons/OSDs)
- `terraform/csi-test/` — smoke‑test workload
- Migration guides under `docs/guides/cephfs-to-csi-rbd-migration.md`
  and `docs/guides/csi-rbd-storage-overview.md`
- Migrations from CephFS to RBD for: MongoDB, MariaDB, Postgres, Loki,
  Prometheus, Neo4j, Qdrant (data preservation via dump/restore)

**Application deployments**
- Storage / observability: MinIO, Loki, Tempo, Prometheus, Grafana,
  Alertmanager, Alloy, Uptime‑Kuma, Gatus
- Databases / queues: MongoDB 3‑node replica set (with Docker driver
  and CSI RBD volumes), MariaDB‑backup, Postgres‑backup
- Productivity / chat: Rocket.Chat, Docmost, aippt, n8n, Searxng,
  Linkding, Linkwarden, Plantuml, Excalidraw, IT‑Tools, Gitea,
  Homepage, Nautobot, Phoenix, Bastionclaw
- Networking / IPAM: dns, dns‑lab, unifi, librenms, mqtt, ntfy

**OpenClaw gateway + knowledge layer**
- `terraform/openclaw-gateway/` — multi‑agent gateway, botctl CLI
  wrapper, CephFS‑backed config and workspaces, per‑team configs
  (default + knowledge), clawnerd cron agent
- Knowledge‑layer agents: Archivist (coordinator), Vec‑Ingest,
  Graph‑Ingest, Notes‑Ingest
- `terraform/litellm/` — LiteLLM proxy fronting local vLLM and
  commercial LLM APIs
- Knowledge backends: `terraform/neo4j/`, `terraform/qdrant/`,
  `terraform/nats/`, `terraform/falkordb/`, `terraform/graphiti/`
- Rocket.Chat integration, OpenClaw v2026.3.12 upgrade validation,
  selfhost discovery agent PRD, openclaw‑add‑bot.sh

**Documentation**
- Sphinx site source under `docs/sphinx/` (architecture, getting
  started, services, operations, runbooks, demos, OpenClaw)
- Guides under `docs/guides/` for OpenClaw deployment, Rocket.Chat
  integration, post‑deployment setup, CSI migration
- 40+ dated design docs and implementation plans under `docs/plans/`
- Postmortem: 2026‑03‑11 cluster‑wide container‑kill incident
- README rewrite reflecting the VM‑default, GPU, CSI, and OpenClaw
  story; this CHANGELOG

### Changed

- Default base image upgraded from Debian 12 (Bookworm) to Debian 13
  (Trixie); HashiCorp APT repo and base image scripts updated to match
- Nomad scheduler algorithm set to `spread` for even workload
  distribution across nodes
- HAProxy fronts the cluster control plane on alternate ports to avoid
  conflicts with libvirt bridge IPs

### Fixed

- Rootless Nomad agent's Docker GC was killing root‑agent containers
  every ~10 minutes when both agents shared the Docker socket. Fix:
  explicit `plugin "docker"` block in the rootless agent config with
  `gc { container = false; image = false; dangling_containers { enabled
  = false } }`; remove the duplicate `docker.hcl` so all Docker config
  lives in `nomad-agent-root.hcl.j2` only
- CSI node plugin requires `network_mode = "host"`; without it, kernel
  RBD client lands in the container netns and gets `-101 ENETUNREACH`
  with D‑state processes that survive only a VM reboot
- CephFS is not auto‑mounted after VM reboot; `playbooks/10-cluster-
  start.yml` now handles this
- MongoDB 8 keyfile auth: rejects keyfiles on CephFS / tmpfs / overlay
  / Nomad `local/`. Workaround: `prestart` init task writes keyfile to
  the CSI volume (ext4 on RBD)
- PostgreSQL refuses to initialize over an ext4 `lost+found`; use a
  PGDATA subdirectory like `/appdata/postgres/data`

### Removed

- `homelab.yml` — legacy single‑file playbook, superseded by the
  `playbooks/00..12` lifecycle
- `terraform/op/` — 1Password setup helper, folded into `roles/secrets`
  and `roles/seed-onepassword`
- `terraform/traefik/dynamic.toml` — unused empty stub

### Security

- Untrack `inventory/group_vars/all.yml`, `**/*.tfvars`, and
  `**/*.auto.tfvars` going forward (with `*.tfvars.example` exception)
- Replace hardcoded Cloudflare tunnel token in
  `terraform/homeassitant/homeassistant.nomad.hcl` and Jupyter
  IdentityProvider token in `terraform/jupyter/jupyter.nomad.hcl` with
  `REPLACE_VIA_NOMAD_VARIABLE` placeholders. The original tokens
  remain in upstream history prior to the squash and are example/dev
  values — rotate if they were ever wired to a real deployment

---

## [0.1.0] — 2026‑02‑21

Initial public release covering the original bare‑metal 3‑node lab
framework with HashiCorp Consul + Nomad, Podman, Traefik, Tailscale,
1Password, and a first‑pass service catalog (Postgres, MariaDB, Redis,
ChromaDB, Weaviate, Grafana, Loki, Jupyter, Open‑WebUI, and others).
See `git log 2417da0` for the original commit set.
