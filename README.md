```
 ________  ________ _________  ________  ________   _________
|\   __  \|\   ____\\___   ___\\   __  \|\   ___  \|\___   ___\
\ \  \|\  \ \  \___\|___ \  \_\ \  \|\  \ \  \\ \  \|___ \  \_|
 \ \  \\\  \ \  \       \ \  \ \ \   __  \ \  \\ \  \   \ \  \
  \ \  \\\  \ \  \____   \ \  \ \ \  \ \  \ \  \\ \  \   \ \  \
   \ \_______\ \_______\  \ \__\ \ \__\ \__\ \__\\ \__\   \ \__\
    \|_______|\|_______|   \|__|  \|__|\|__|\|__| \|__|    \|__|
    1password   Consul  Terraform   Ansible    Nomad    Tailscale

                   An opinionated lab framework
```

Octant is an opinionated infrastructure‑as‑code framework for standing up
a HashiCorp Nomad / Consul / Ceph lab from scratch. It targets either a
3‑node bare‑metal cluster or a 3‑VM cluster built on a libvirt
hypervisor (the default), with optional integration of an AMD Instinct
GPU host as a workload‑bearing client.

The repo glues together Packer, Ansible, Terraform, Consul, Nomad,
Podman, Docker, Ceph, Traefik, Tailscale, and 1Password into a single
`make`‑driven workflow, plus a catalog of ~60 Nomad jobs covering
databases, observability, agent platforms, and end‑user applications.

## Features

**Cluster foundation**
- VM‑based deployment on a libvirt hypervisor (Debian 13 / Trixie cloud
  image) with a Packer‑style golden base image
- Or bare‑metal 3‑node deployment via the same role set
- HashiCorp Consul + Nomad with paired root and rootless Podman agents
  on every node
- Docker driver alongside Podman for jobs that require it (Ceph CSI,
  MongoDB replica set)
- Optional GPU‑bearing hypervisor node joined as a Nomad client for
  ROCm / vLLM workloads
- CephFS for shared filesystem state and Ceph RBD (via the `ceph-csi`
  Nomad CSI plugin) for block volumes
- Traefik with LetsEncrypt + Cloudflare DNS‑01 for ingress; HAProxy as
  the front‑door TCP load balancer
- Tailscale mesh for on‑prem ↔ cloud connectivity; free‑tier GCP
  Terraform module to extend the cluster
- 1Password backed secrets, surfaced via Nomad variables

**Day‑2 operations**
- `make deploy` / `make deploy-host` / `make deploy-role` for targeted
  Ansible runs
- Graceful cluster shutdown, cold qcow2 snapshotting, and ordered
  cluster start with health‑check validation
- Per‑service Terraform modules under `terraform/<service>/` with a
  shared template for new services
- Automated backups to S3‑compatible endpoints with Restic, plus
  database‑specific dump jobs for Postgres / MariaDB / MongoDB

**Service catalog (selected)**
- Storage / observability: MinIO, Loki, Tempo, Prometheus, Grafana,
  Alertmanager, Alloy, Uptime‑Kuma, Gatus
- Databases / queues: Postgres, MariaDB, MongoDB (3‑node replica set),
  Redis, Neo4j, Qdrant, FalkorDB, NATS, ChromaDB, Weaviate
- LLM / agent platform: vLLM (Gemma‑4 31B on AMD Instinct), LiteLLM
  proxy, OpenClaw gateway with multi‑agent skill packs, Jupyter,
  Open‑WebUI, Langfuse, Phoenix, Bastionclaw
- Knowledge layer: Graphiti + Qdrant + Notes ingestion agents
  orchestrated through OpenClaw
- Productivity / chat: Rocket.Chat, Docmost, n8n, Searxng, Linkding,
  Linkwarden, Plantuml, Excalidraw, IT‑Tools, Gitea, Homepage,
  Nautobot, Home Assistant + Music Assistant

## Quick start

```bash
# 0. Configure
cp envrc.example .envrc        # populate secrets, then `direnv allow`
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml

# 1. Build the golden base image on the hypervisor
ansible-playbook playbooks/00-build-base-image.yml -i inventory/hypervisors.yml

# 2. Provision the 3-VM cluster + Ceph + services in order
make deploy

# 3. Optional: join a GPU hypervisor as a Nomad client
make join-hypervisor

# 4. Deploy services
cd terraform/<service> && terraform init && terraform apply -auto-approve
```

The full getting‑started walkthrough lives under
[`docs/sphinx/getting-started.md`](docs/sphinx/getting-started.md); see
the Sphinx site source under [`docs/sphinx/`](docs/sphinx/) for
architecture, runbooks, operations, and demos.

## Quick commands

```bash
# Ansible
make deploy                          # Full cluster deployment
make deploy-host HOST=octant-01      # Single host
make deploy-role ROLE=volumes        # Single role, all hosts
make deploy-role-host ROLE=volumes HOST=octant-01

# Cluster lifecycle
make start-nomad / make stop-nomad
make start-consul / make stop-consul
make shutdown                        # Graceful cluster shutdown
make snapshot                        # Cold qcow2 snapshots
make join-hypervisor                 # Add GPU host as Nomad client

# Nomad / Consul
nomad job status                     # All jobs
nomad alloc logs -job <service>      # Container logs
consul catalog services              # All registered services
consul health state critical         # Failing health checks
```

## Architecture

```
Internet → HAProxy (80/443) → Traefik (Consul catalog) → Nomad services
                                                          ↕
                                Consul DNS (<svc>.service.consul)
                                                          ↕
                                CephFS (shared FS) + Ceph RBD (block)
                                via ceph-csi Nomad CSI plugin
```

- **3 cluster nodes** (`octant-01/02/03`, default `192.168.122.101-103`)
  each running paired Consul/Nomad server + rootless agent + root agent
- **Optional hypervisor node** runs Consul/Nomad client agents with GPU
  devices exposed via `nomad-device-amdgpu`
- **Service discovery** via Consul DNS at `<service>.service.consul`
- **Ingress** through Traefik with Consul catalog provider,
  LetsEncrypt via Cloudflare DNS‑01
- **Storage** mixed: CephFS at `/mnt/services/<svc>/` for most apps,
  Ceph RBD via CSI for performance‑sensitive databases
- **Secrets** in 1Password, surfaced as Nomad variables

## Project structure

```
playbooks/             # Lifecycle playbooks (00-build-base-image through 12-remove-hypervisor)
roles/                 # Ansible roles (consul, nomad, podman, ceph, secrets, ...)
inventory/             # Inventory + group_vars (groups.yml is the SoT)
packer/                # Base image scripts
terraform/<service>/   # Per-service deployment (nomad.hcl + main.tf + variables.tf)
terraform/template/    # Starter template for new services
scripts/               # Helper scripts (e.g. openclaw-add-bot.sh)
docs/                  # Documentation, design docs, postmortems
docs/sphinx/           # Sphinx site source (architecture, runbooks, demos)
docs/plans/            # Dated design docs and implementation plans
CHANGELOG.md           # Release log
```

## Documentation

- [Getting started](docs/sphinx/getting-started.md)
- [Architecture](docs/sphinx/architecture.md)
- [Operations](docs/sphinx/operations.md) and [runbooks](docs/sphinx/runbooks.md)
- [Service catalog](docs/sphinx/services.md)
- [OpenClaw gateway](docs/sphinx/openclaw.md)
- [Guides](docs/guides/) — CephFS→CSI migration, OpenClaw deployment,
  post‑deployment setup
- [Changelog](CHANGELOG.md)

## Diagrams

Initial cluster deployment
![](docs/octant-usage/diagrams/01_architecture.png)

Consul/Nomad architecture
![](docs/octant-usage/diagrams/03_nomad_consul.png)

Ingress with HAProxy and Traefik
![](docs/octant-usage/diagrams/04_ingress_tls.png)

Tailscale overview
![](docs/octant-usage/diagrams/05_tailscale_overview.png)

## FAQ

- **Why?** Octant was born out of a desire to learn — a reliable
  platform to try the numerous AI/LLM projects coming out, and a chance
  to learn Consul and Nomad in production‑shaped configurations. It was
  also a response to rebuilding a home lab from scratch multiple times:
  this time, every part of the build is automated.
- **How much does it cost?** Mostly built with components on hand — a
  1Password subscription (~$60/yr), free Cloudflare and Tailscale
  accounts, and a gaming PC capable of hosting the VM cluster and
  running Ollama / vLLM. Cloud costs have been under $1/month thanks to
  free‑tier GCP. Backups go to Backblaze B2.
- **For the 3‑node architecture, are Consul, Nomad, and Ceph all on the
  same nodes?** Yes — each node runs a Consul server, a Nomad server,
  paired rootless and root Consul/Nomad agents, and a Ceph mon/mgr.
  Both Consul and Nomad use Raft, so the 3‑node minimum gives quorum
  with one‑node tolerance. Running both rootless and root agents lets
  each node host either rootless containers or the few containers that
  require root (GPU access, CSI, privileged networking).
- **How does Traefik fit in?** Traefik runs in a single container (the
  OSS version doesn't cluster). HAProxy fronts ports 80/443 and proxies
  to Traefik, which then uses Consul service discovery + container tags
  to terminate TLS and route requests.

## Inspiration

- https://github.com/perrymanuk/hashi-homelab
- https://github.com/assareh/home-lab
- https://github.com/abaschen/nomad-consul-vault

## License

This project is licensed under the [MIT License](./LICENSE).
