# Architecture

## Component Overview

```
┌─────────────────────────────────────────────────────┐
│                     HAProxy                          │
│              (hypervisor, :80/:443)                   │
└────────────────────┬────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
   octant-01    octant-02    octant-03
   ┌────────┐  ┌────────┐  ┌────────┐
   │ Consul │  │ Consul │  │ Consul │  ← Service discovery, DNS, KV
   │ Nomad  │  │ Nomad  │  │ Nomad  │  ← Workload scheduling
   │Podman/ │  │Podman/ │  │Podman/ │  ← Container runtimes
   │ Docker │  │ Docker │  │ Docker │
   │ Ceph   │  │ Ceph   │  │ Ceph   │  ← Distributed storage
   └────────┘  └────────┘  └────────┘
        │            │            │
        └────────────┼────────────┘
              ┌──────┴──────┐
              ▼             ▼
    CephFS (/mnt/services)  CSI RBD (ext4 block devices)
```

## Component Roles

### Consul
- **Service discovery:** Every Nomad job registers as a Consul service
- **DNS:** Services resolve via `<name>.service.consul`
- **KV store:** Terraform state backend for all service modules
- **Health checks:** Consul monitors service health and feeds Traefik
- **Deployment:** 3 servers (quorum) + 6 agents (2 per node: rootless + root)
- **Ports:** 8500 (server), 9500 (agent), 10500 (root agent)

### Nomad
- **Scheduling:** Places containerized workloads across the 3-node cluster
- **Job types:** `service` (long-running), `batch` (periodic tasks like backups), `system` (one per node)
- **Drivers:** Podman (rootless agents) and Docker (root agents / CSI workloads)
- **CSI support:** `ceph-csi` plugin provides RBD block device volumes
- **Deployment:** 3 servers + 6 agents (matching Consul agent topology)
- **Ports:** 4646 (server), 5646 (agent), 6646 (root agent)

### Container Runtimes
- **Podman (rootless agents):** Default for stateless or CephFS-backed services. Security-first via rootless containers with user namespace remapping.
- **Docker (root agents):** Used for CSI-backed services that need block device volumes. Required because CSI node plugins only run on root agents.
- **Paired agents:** Each node runs a rootless (`octant-0N-agent`) and a root (`octant-0N-agent-root`) Nomad+Consul agent pair.

### Traefik
- **Reverse proxy:** Routes external HTTPS traffic to backend services
- **Consul Catalog provider:** Auto-discovers services from Consul
- **TLS:** Handles Let's Encrypt certificates for `*.lab.shamsway.net`
- **Dashboard:** Available at `https://traefik.lab.shamsway.net`

### Ceph
- **Version:** 16.2.15 (Pacific), deployed via cephadm
- **Topology:** 3 OSDs (one per node, 100 GB data disk each), 2x replication = ~127 GiB usable
- **CephFS:** `octant-services` filesystem mounted at `/mnt/services` on all nodes
- **RBD:** `nomad-csi` pool provides dedicated ext4 block devices via the CSI plugin
- **Purpose:** Shared storage (CephFS) for config and low-IO workloads; isolated block devices (RBD) for databases and high-IO services

### HAProxy
- **Location:** Runs on the hypervisor host
- **Role:** Load balances external traffic across the 3 cluster nodes to Traefik
- **Ports:** 80 (HTTP), 443 (HTTPS), 9002 (Traefik dashboard)

## Request Flow

```
Client → DNS (*.lab.shamsway.net)
       → HAProxy (:443)
       → Traefik (Consul Catalog routing)
       → Nomad-scheduled container (Podman or Docker)
       → Data on CephFS or CSI RBD
```

1. DNS resolves `<service>.lab.shamsway.net` to the cluster's Tailscale IP
2. HAProxy terminates the connection and forwards to Traefik on the cluster
3. Traefik uses Consul Catalog to find the backend service and its healthy instances
4. The request reaches the container (Podman on rootless agents, Docker on root agents)
5. Service data is stored on CephFS (shared, any node) or CSI RBD (dedicated block device, pinned node)

## Storage Architecture

The cluster uses a dual storage model. Both storage types share the same Ceph
OSDs and replication factor, but serve different workload profiles.

```
Physical: /dev/vdb (100 GB raw disk per node × 3 = 300 GB raw)
    ↓
Ceph OSD (3 OSDs, replication factor 2, ~127 GiB usable)
    ├──────────────────────────┐
    ↓                          ↓
CephFS (octant-services)     RBD pool (nomad-csi)
    ↓                          ↓
Kernel mount on all nodes    CSI plugin mounts per-alloc
/mnt/services/<service>/     ext4 block device → container
    ↓                          ↓
Podman bind mounts           Docker volume_mount
(rootless agents)            (root agents, pinned node)
```

### CephFS — Shared Filesystem

Used for configuration, static content, and low-IO workloads. CephFS is mounted
at `/mnt/services/` on all nodes, so services can be rescheduled freely.

- **Nomad volume type:** `host`
- **Driver:** Podman (rootless agents)
- **Node pinning:** Not required — data accessible from any node
- **Services:** Traefik, Grafana, n8n, Gitea, Homepage, Nginx, and other
  application workloads

### CSI RBD — Dedicated Block Devices

Used for databases and high-IO services that benefit from I/O isolation. Each
volume is a dedicated Ceph RBD image formatted as ext4, mounted via the Nomad
CSI plugin.

- **Nomad volume type:** `csi`
- **Driver:** Docker (root agents only — CSI node plugin requires root)
- **Node pinning:** Required — `single-node-writer` volumes bind to one node
- **Thin provisioned:** Volumes only consume space as data is written
- **Volume init:** Each service uses a `busybox` prestart task to `chown` the
  volume to the app's UID before the main task starts

| Service | Volume ID | Size | UID | Node |
|---------|-----------|------|-----|------|
| MongoDB (×3) | `mongodb-N-data` | 5 GiB each | 999:999 | octant-01/02/03-agent-root |
| Prometheus | `prometheus-data` | 10 GiB | 65534:65534 | octant-01-agent-root |
| PostgreSQL | `postgres-data` | 5 GiB | 999:999 | octant-01-agent-root |
| MariaDB | `mariadb-data` | 5 GiB | 999:999 | octant-01-agent-root |
| Loki | `loki-data` | 5 GiB | 10001:10001 | octant-01-agent-root |
| Neo4j | `neo4j-data` | 5 GiB | 7474:7474 | octant-01-agent-root |
| Qdrant | `qdrant-data` | 5 GiB | 1000:1000 | octant-01-agent-root |

### Design Rationale

CephFS remains the right choice for services that:
- Need to float between nodes (no node pinning)
- Have low I/O requirements (config files, static assets)
- Benefit from shared access (multiple jobs reading the same files)

CSI RBD is preferred for services that:
- Perform heavy write I/O (databases, log/metric storage)
- Need filesystem guarantees (MongoDB 8 rejects non-standard filesystems)
- Benefit from I/O isolation (no contention with other services)
- Can tolerate node pinning (single-instance databases)

## Secrets Management

Secrets are managed through **1Password** and **direnv**:

1. Secrets are stored in a 1Password vault
2. `.envrc` loads secrets into environment variables via `op` CLI
3. Ansible and Terraform consume secrets from the environment
4. Nomad jobs receive secrets via Terraform template variables

## Terraform State

All Terraform modules store state in **Consul KV** at `terraform/state/<service>`.
This keeps state within the cluster and eliminates external dependencies.
