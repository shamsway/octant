# MongoDB Deployment Design

**Date**: 2026-03-03
**Reference**: docs/plans/2026-02-27-autodeploy-candidates-design.md (section I1)

## Overview

Deploy MongoDB 7 as a shared infrastructure service on the Octant homelab, following the existing MariaDB deployment pattern. MongoDB will run in replica set mode (required by downstream apps like Rocket.Chat and LibreChat that use change streams/oplog).

## Architecture

- **Image**: `mongo:7` (official Docker Hub)
- **Port**: 27017 (static, consistent with other database services)
- **Type**: `service` (long-running)
- **Constraint**: rootless, linux
- **Service discovery**: Consul at `mongodb.service.consul:27017`

## Configuration

### Command Arguments

```
mongod --replSet rs0 --oplogSize 128
```

- `--replSet rs0`: Enable replica set mode (single-member for this lab)
- `--oplogSize 128`: Limit oplog to 128MB (sufficient for homelab workload)

### Authentication

- `MONGO_INITDB_ROOT_USERNAME=admin`
- `MONGO_INITDB_ROOT_PASSWORD` via 1Password → Nomad variables
- 1Password item: `service_mongodb` in "Octant" vault

### Volumes

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `/mnt/services/mongodb/data` | `/data/db` | Database files |
| `/mnt/services/mongodb/configdb` | `/data/configdb` | Configuration |

### Health Check

- **Type**: TCP on port 27017 (consistent with Postgres/MariaDB/Redis)
- **Interval**: 30s
- **Timeout**: 5s

### Resources

- **CPU**: 200 MHz
- **Memory**: 512 MB (WiredTiger engine needs more than simpler databases)

## Files

```
terraform/mongodb/
├── mongodb.nomad.hcl   # Nomad job spec
├── main.tf             # Terraform + 1Password + Nomad variable
└── variables.tf        # Standard lab defaults
```

## Post-Deploy: Replica Set Initialization

After `terraform apply`, manually initialize the replica set:

```bash
nomad alloc exec -job mongodb mongosh --eval \
  "rs.initiate({_id:'rs0', members:[{_id:0, host:'localhost:27017'}]})"
```

This is a one-time operation. The replica set config persists in the data volume.

## Prerequisites

1. Create `service_mongodb` item in 1Password "Octant" vault with a password
2. Add volumes (`mongodb/data`, `mongodb/configdb`) to `inventory/groups.yml`
3. Run volume playbook: `playbooks/05-deploy-volumes.yml`

## Design Decisions

- **Static port 27017**: Matches pattern of other databases (Postgres 5432, MariaDB 3306, Redis 6379) for direct access via Consul DNS
- **No Traefik routing**: Database-only service with no web UI (unlike MongoDB Express or similar)
- **Manual RS init**: Simpler than lifecycle hooks; one-time operation that persists across restarts
- **rootless**: MongoDB runs fine in rootless mode; no privileged access needed
