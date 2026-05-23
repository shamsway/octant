# Lab Overview

## What Is Octant?

Octant is a 3-node homelab cluster running on KVM virtual machines. It provides a
production-style platform for containerized services using HashiCorp Consul and Nomad
with Podman as the container runtime, backed by Ceph shared storage.

The cluster runs 30+ services spanning monitoring, databases, AI/ML tooling, and
general-purpose applications — all managed through Ansible playbooks, Terraform
modules, and a central Makefile.

## Nodes

All three nodes are identical Debian 12 KVM VMs on a single hypervisor:

| Host      | IP              | RAM  | vCPUs | OS Disk | Data Disk | Container Disk |
|-----------|-----------------|------|-------|---------|-----------|----------------|
| octant-01 | 192.168.122.101 | 8 GB | 2     | 60 GB   | 100 GB    | 30 GB          |
| octant-02 | 192.168.122.102 | 8 GB | 2     | 60 GB   | 100 GB    | 30 GB          |
| octant-03 | 192.168.122.103 | 8 GB | 2     | 60 GB   | 100 GB    | 30 GB          |

Each node runs:
- **Consul** server + agent (service discovery, DNS, KV store)
- **Nomad** server + agent (workload scheduling)
- **Podman** rootless + rootful (container runtime)
- **Ceph** OSD (distributed storage)

## Network Topology

```
Internet
  │
  ├── Tailscale overlay (multi-region mesh)
  │
  ├── HAProxy (hypervisor, 192.168.122.1)
  │     ├── :80  → Traefik HTTP
  │     ├── :443 → Traefik HTTPS
  │     └── :9002 → Traefik dashboard
  │
  └── KVM bridge (192.168.122.0/24)
        ├── octant-01  .101
        ├── octant-02  .102
        └── octant-03  .103
```

- **External access:** HAProxy on the hypervisor load-balances to Traefik on the cluster
- **Service discovery:** Consul DNS (`.service.consul`)
- **Public DNS:** `*.lab.shamsway.net` via Cloudflare, pointing to the Tailscale IP
- **Internal DNS:** `*.octant.local` via Consul

## What It Runs

The cluster runs services across several categories:

- **Monitoring:** Prometheus, Grafana, Loki, Tempo, Alertmanager, Alloy, Gatus, Uptime Kuma
- **Databases:** PostgreSQL, MariaDB, Redis, Qdrant
- **AI/ML:** Phoenix (LLM observability), LiteLLM (LLM proxy), SearXNG (search)
- **Apps:** Excalidraw, Homepage, n8n, pgAdmin, Nginx
- **Infrastructure:** Traefik (reverse proxy), MQTT (Mosquitto)

All services are deployed as Nomad jobs via Terraform, with data stored on CephFS-backed
host volumes at `/mnt/services/`.

## Key URLs

| Service     | URL                                      |
|-------------|------------------------------------------|
| Consul UI   | `https://consul.lab.shamsway.net`        |
| Nomad UI    | `https://nomad.lab.shamsway.net`         |
| Grafana     | `https://grafana.lab.shamsway.net`       |
| Prometheus  | `https://prometheus.lab.shamsway.net`    |
| Gatus       | `https://gatus.lab.shamsway.net`         |
| Traefik     | `https://traefik.lab.shamsway.net`       |
| Homepage    | `https://homepage.lab.shamsway.net`      |
