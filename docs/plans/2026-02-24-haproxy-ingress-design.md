# HAProxy Ingress on Hypervisor - Design

**Date:** 2026-02-24
**Branch:** `feature/app-migration`

## Problem

The octant VM cluster runs Traefik, Nomad, and Consul on three VMs (192.168.122.101-103) inside a libvirt network. The hypervisor host is the only externally reachable machine. Currently there is no load balancer on the hypervisor to route inbound traffic to the cluster. Users access services by SSH tunneling directly to individual VM IPs.

The existing `ingress-lb` Nomad job (nginx) handles intra-cluster load balancing from host ports to Traefik via Consul service discovery. This design adds an external-facing layer on the hypervisor itself.

## Design

### Architecture

```
SSH tunnel / local access
       |
       v
+-------------------------------+
|  Hypervisor (HAProxy)         |
|  :443  -> TCP passthrough     |
|  :4646 -> TCP passthrough     |
|  :8500 -> TCP passthrough     |
|                               |
|  Backend pool (per frontend): |
|    192.168.122.101            |
|    192.168.122.102            |
|    192.168.122.103            |
|                               |
|  Active health checks:        |
|    TCP connect every 5s       |
|    3 failures = mark down     |
|    2 successes = mark up      |
+---------------+---------------+
                |
        +-------+-------+
        v       v       v
     octant-01  02     03
     (ingress-lb on 443 -> Traefik)
     (Nomad API on 4646)
     (Consul API on 8500)
```

### Proxied Ports

| Frontend | Backend Port | Service | Mode |
|----------|-------------|---------|------|
| :443 | :443 | Traefik HTTPS (via ingress-lb) | TCP passthrough |
| :4646 | :4646 | Nomad HTTP API | TCP passthrough |
| :8500 | :8500 | Consul HTTP API | TCP passthrough |

All frontends use TCP mode (layer 4). No TLS termination on the hypervisor - Traefik continues to handle ACME/Cloudflare cert management.

### Health Checks

HAProxy active TCP health checks on each backend port:
- `inter 5s` - check every 5 seconds
- `fall 3` - mark down after 3 consecutive failures
- `rise 2` - mark up after 2 consecutive successes
- `balance roundrobin` - distribute across healthy backends

### Implementation

**New role: `roles/haproxy/`**
- `tasks/main.yml` - install haproxy, template config, enable and start service
- `templates/haproxy.cfg.j2` - HAProxy config with backends from inventory

**New playbook: `playbooks/02.5-deploy-haproxy.yml`**
- Targets `hypervisors` group
- Runs after cluster deploy (Consul/Nomad listening) but before Ceph/services

**Makefile target: `deploy-haproxy`**
- Uses hypervisor inventory: `-i inventory/hypervisors.yml -i inventory/groups.yml`
- Inserted into `deploy-vm` pipeline between `deploy-cluster` and `deploy-ceph`

### Role Structure

Follows existing project conventions (tasks + templates, no separate defaults/handlers dirs).

```
roles/haproxy/
  tasks/main.yml      - install, template, enable, start, verify
  templates/
    haproxy.cfg.j2    - full HAProxy config
```

### Pipeline Position

```
deploy-vm: build-base-image provision-vms deploy-cluster deploy-haproxy deploy-ceph deploy-services health-check
                                              ^^^^^^^^^^^^^^^^^
                                              new step
```

### SSH Tunnel Access

Users access the hypervisor via SSH tunnel. The following local port forwards provide access to cluster services through HAProxy:

```
LocalForward 8443 localhost:443      # Traefik HTTPS
LocalForward 4646 localhost:4646     # Nomad API
LocalForward 8500 localhost:8500     # Consul API
```

### Decisions

- **HAProxy over nginx**: native active health checks, purpose-built for load balancing
- **TCP passthrough**: no TLS termination on hypervisor, Traefik manages certs
- **All 3 VMs as backends**: round-robin with health-aware failover
- **Phase 02.5**: needs Consul/Nomad listening but not services deployed
