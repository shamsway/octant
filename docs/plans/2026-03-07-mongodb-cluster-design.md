# MongoDB 3-Node Replica Set Design

## Status: Approved

## Context

MongoDB runs as a single-node replica set (`rs0`) on Nomad/Podman. Rocket.Chat requires a replica set for oplog access. The single-node topology has a recurring problem: when the container restarts, MongoDB loses its primary election state and requires manual `rs.reconfig({force: true})` to recover. This causes Rocket.Chat downtime until someone intervenes.

**Current state:**
- MongoDB 8.0.19, single node, image `docker.io/mongo:8.0`
- Replica set `rs0` with keyfile auth
- Data on CephFS at `/mnt/services/mongodb/`
- Single consumer (Rocket.Chat), with plans for multi-tenant use

## Decision

Deploy a 3-node MongoDB replica set using 3 separate Nomad service jobs, one per cluster node. Each member gets its own CSI RBD volume for independent storage. This eliminates the single-node election failure and provides automatic failover.

Fresh start — no data migration from the existing single-node instance.

## Architecture

```
                    Rocket.Chat / other consumers
                              |
    mongodb://mongodb-1:27017,mongodb-2:27017,mongodb-3:27017/?replicaSet=rs0
                              |
          +-------------------+-------------------+
          |                   |                   |
    +-----+-----+       +-----+-----+       +-----+-----+
    | mongodb-1 |       | mongodb-2 |       | mongodb-3 |
    |  PRIMARY  |<----->| SECONDARY |<----->| SECONDARY |
    | octant-01 |       | octant-02 |       | octant-03 |
    +-----+-----+       +-----+-----+       +-----+-----+
          |                   |                   |
     CSI RBD vol         CSI RBD vol         CSI RBD vol
    (independent)       (independent)       (independent)
```

## Terraform Structure

Single Terraform module in `terraform/mongodb/` using `for_each` over the 3 members. One `.nomad.hcl` template produces 3 Nomad jobs.

```hcl
variable "members" {
  default = {
    "mongodb-1" = { node = "octant-01" }
    "mongodb-2" = { node = "octant-02" }
    "mongodb-3" = { node = "octant-03" }
  }
}

resource "nomad_job" "mongodb" {
  for_each = var.members
  jobspec  = templatefile("${path.module}/mongodb.nomad.hcl", {
    servicename = each.key
    node_name   = each.value.node
    ...
  })
}
```

Rolling upgrades target individual members: `terraform apply -target='nomad_job.mongodb["mongodb-2"]'`.

## Nomad Job Spec

Each job is a `service` type pinned to a specific node.

### Node Constraint

```hcl
constraint {
  attribute = "$${node.unique.name}"
  value     = "${node_name}"
}
```

### Volumes

CSI RBD volumes for data. Keyfile stays on shared CephFS (read-only, already mounted on all nodes).

```hcl
volume "mongodb-data" {
  type            = "csi"
  source          = "${servicename}-data"
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

task "mongodb" {
  volume_mount {
    volume      = "mongodb-data"
    destination = "/data/db"
  }

  config {
    volumes = [
      "/mnt/services/mongodb/keyfile:/etc/mongodb/keyfile"
    ]
  }
}
```

### Service Registration

Each member registers its own Consul service. Homepage/Traefik tags only on `mongodb-1` to avoid duplicate dashboard entries.

```hcl
service {
  name = "${servicename}"   # mongodb-1, mongodb-2, mongodb-3
  tags = ["mongodb-replica-set=rs0"]
}
```

### Resources

```hcl
resources {
  cpu    = 200
  memory = 1024
}
```

### Networking

Static port 27017 on all nodes (one instance per node, no conflicts).

## Replica Set Initialization

A `poststart` lifecycle task on `mongodb-1` only. Runs `rs.initiate()` if the replica set isn't already configured. Idempotent — checks `rs.status()` first.

```hcl
task "rs-init" {
  lifecycle {
    hook    = "poststart"
    sidecar = false
  }

  driver = "podman"
  config {
    image = "${image}"
    args  = [
      "mongosh", "--host", "localhost:27017",
      "-u", "admin", "-p", "<from nomad var>",
      "--authenticationDatabase", "admin",
      "--eval", "try { rs.status(); } catch(e) { rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: 'mongodb-1.service.consul:27017' }, { _id: 1, host: 'mongodb-2.service.consul:27017' }, { _id: 2, host: 'mongodb-3.service.consul:27017' } ] }); }"
    ]
  }
}
```

Once initiated, the replica set is self-managing. If any single member restarts, the other two maintain quorum and elect a new primary automatically.

## Consumer Connection Strings

### Rocket.Chat

```hcl
MONGO_URL=mongodb://user:pass@mongodb-1.service.consul:27017,mongodb-2.service.consul:27017,mongodb-3.service.consul:27017/rocketchat?replicaSet=rs0&authSource=admin
MONGO_OPLOG_URL=mongodb://user:pass@mongodb-1.service.consul:27017,mongodb-2.service.consul:27017,mongodb-3.service.consul:27017/local?replicaSet=rs0&authSource=admin
```

### Future Consumers

Same host list pattern. The `replica_set_members` Terraform variable provides the host list.

## Credentials

Shared `nomad_variable` at `nomad/jobs/mongodb` (existing). All 3 members read from the same variable path. Per-database user credentials managed separately for each consumer.

## Failure Scenarios

| Scenario | Behavior |
|----------|----------|
| 1 member down | Automatic failover, remaining 2 elect primary |
| 2 members down | Cluster read-only, no primary. Recovers when 2nd member returns |
| All 3 down | Recovers automatically when quorum (2+) comes back with consistent data |
| Node replacement | Reseed new member from existing replica set |

## Prerequisites

- Nomad CSI plugin for Ceph RBD (controller + node components)
- 3 RBD volumes provisioned (static or dynamic)
- Existing keyfile on CephFS accessible from all nodes (already true)

## Migration Path

1. Deploy CSI plugin and provision RBD volumes
2. Deploy 3-node MongoDB cluster (fresh)
3. Create Rocket.Chat database and user on new cluster
4. Update Rocket.Chat connection strings
5. Redeploy Rocket.Chat (fresh start)
6. Decommission old single-node MongoDB
