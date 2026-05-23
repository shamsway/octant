# MongoDB 3-Node Replica Set Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace single-node MongoDB with a 3-node replica set using CSI RBD volumes for automatic failover.

**Architecture:** Three separate Nomad service jobs (`mongodb-1`, `mongodb-2`, `mongodb-3`), each pinned to a cluster node via node constraint. One Terraform module with `for_each` produces all 3 jobs from a single template. A poststart lifecycle task on `mongodb-1` handles replica set initialization.

**Tech Stack:** Terraform, Nomad HCL, Podman, MongoDB 8.0, Consul DNS

**Design doc:** `docs/plans/2026-03-07-mongodb-cluster-design.md`

**Prerequisite:** CSI RBD volumes must be available before Task 3. Tasks 1-2 can proceed without CSI.

---

### Task 1: Update `variables.tf` for multi-member support

**Files:**
- Modify: `terraform/mongodb/variables.tf`

**Step 1: Replace `servicename` with `members` map and add `mongo_hosts` variable**

Replace the entire contents of `terraform/mongodb/variables.tf` with:

```hcl
variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
}

variable "nomad" {
  description = "Nomad server address"
  type        = string
  default     = "localhost"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}

variable "image" {
  type    = string
  default = "docker.io/mongo:8.0"
}

variable "members" {
  description = "MongoDB replica set members: name -> node mapping"
  type        = map(object({ node = string }))
  default = {
    "mongodb-1" = { node = "octant-01" }
    "mongodb-2" = { node = "octant-02" }
    "mongodb-3" = { node = "octant-03" }
  }
}

variable "mongo_hosts" {
  description = "Comma-separated host list for replica set connection strings"
  type        = string
  default     = "mongodb-1.service.consul:27017,mongodb-2.service.consul:27017,mongodb-3.service.consul:27017"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
```

**Step 2: Verify syntax**

Run: `cd terraform/mongodb && terraform validate`
Expected: Success (may warn about unused variables until main.tf is updated)

**Step 3: Commit**

```bash
git add terraform/mongodb/variables.tf
git commit -m "refactor(mongodb): update variables for 3-node replica set"
```

---

### Task 2: Update `main.tf` to use `for_each`

**Files:**
- Modify: `terraform/mongodb/main.tf`

**Step 1: Replace the `nomad_job` resource with `for_each`**

Replace the entire contents of `terraform/mongodb/main.tf` with:

```hcl
terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_password" "mongodb_keyfile" {
  length  = 756
  special = false
}

provider "nomad" {
  address = "http://${var.nomad}:4646"
}

provider "onepassword" {
  # Authenticates via OP_SERVICE_ACCOUNT_TOKEN environment variable
}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "mongodb_root" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_mongodb"
}

resource "nomad_variable" "mongodb" {
  path = "nomad/jobs/mongodb"
  items = {
    root_username  = data.onepassword_item.mongodb_root.username
    root_password  = data.onepassword_item.mongodb_root.password
    keyfile_secret = random_password.mongodb_keyfile.result
  }
}

resource "nomad_job" "mongodb" {
  for_each = var.members
  jobspec = templatefile("${path.module}/mongodb.nomad.hcl", {
    region      = var.region
    datacenter  = var.datacenter
    image       = var.image
    dns         = jsonencode(var.dns)
    servicename = each.key
    node_name   = each.value.node
    is_primary  = each.key == "mongodb-1"
    mongo_hosts = var.mongo_hosts
  })
  depends_on = [nomad_variable.mongodb]
}
```

Key changes:
- `nomad_job.mongodb` uses `for_each = var.members`
- Passes `node_name` for per-node constraint
- Passes `is_primary` flag (only `mongodb-1` gets the rs-init task)
- Passes `mongo_hosts` for the rs.initiate() member list
- `nomad_variable` path stays at `nomad/jobs/mongodb` (shared across all 3 jobs)

**Step 2: Verify syntax**

Run: `terraform validate`
Expected: Success

**Step 3: Commit**

```bash
git add terraform/mongodb/main.tf
git commit -m "refactor(mongodb): use for_each to create 3 replica set members"
```

---

### Task 3: Rewrite `mongodb.nomad.hcl` for clustered deployment

**Files:**
- Modify: `terraform/mongodb/mongodb.nomad.hcl`

**Step 1: Replace the entire Nomad job template**

Replace the entire contents of `terraform/mongodb/mongodb.nomad.hcl` with:

```hcl
job "${servicename}" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  constraint {
    attribute = "$${node.unique.name}"
    value     = "${node_name}"
  }

  group "mongodb" {
    count = 1

    volume "mongodb-data" {
      type            = "csi"
      source          = "${servicename}-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      port "mongodb" {
        static = 27017
        to     = 27017
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      task     = "mongodb"
      port     = "mongodb"

      tags = [
        "alloc=$${NOMAD_ALLOC_ID}",
        "mongodb-replica-set=rs0",
%{ if is_primary ~}
        "homepage.group=Databases",
        "homepage.name=MongoDB",
        "homepage.icon=mongodb",
        "homepage.description=Document DB (rs0)",
%{ endif ~}
      ]

      check {
        name     = "alive"
        type     = "tcp"
        port     = "mongodb"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "mongodb" {
      driver = "podman"

      volume_mount {
        volume      = "mongodb-data"
        destination = "/data/db"
      }

      config {
        image              = "${image}"
        ports              = ["mongodb"]
        image_pull_timeout = "15m"

        args = [
          "mongod",
          "--replSet", "rs0",
          "--oplogSize", "128",
          "--bind_ip_all",
          "--keyFile", "/etc/mongodb/keyfile"
        ]

        volumes = [
          "/mnt/services/mongodb/keyfile:/etc/mongodb/keyfile"
        ]

        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
      }

      env {
        TZ = "America/New_York"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/mongodb" }}MONGO_INITDB_ROOT_USERNAME={{ .root_username }}
MONGO_INITDB_ROOT_PASSWORD={{ .root_password }}{{ end }}
EOT
      }

      resources {
        cpu    = 200
        memory = 1024
      }
    }

%{ if is_primary ~}
    task "rs-init" {
      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      driver = "podman"

      config {
        image = "${image}"

        args = [
          "mongosh", "--host", "localhost:27017",
          "-u", "admin",
          "--authenticationDatabase", "admin",
          "--quiet",
          "--eval", <<-SCRIPT
            sleep(5000);
            try {
              var status = rs.status();
              print("Replica set already initialized: " + status.set);
            } catch(e) {
              print("Initializing replica set rs0...");
              rs.initiate({
                _id: "rs0",
                members: [
                  { _id: 0, host: "mongodb-1.service.consul:27017" },
                  { _id: 1, host: "mongodb-2.service.consul:27017" },
                  { _id: 2, host: "mongodb-3.service.consul:27017" }
                ]
              });
              print("Replica set initiated");
            }
          SCRIPT
        ]
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/mongodb" }}MONGOSH_PASSWORD={{ .root_password }}{{ end }}
EOT
      }

      # mongosh reads password from MONGOSH_PASSWORD when -p is not given
      # but -u is set. This avoids putting the password in args.

      resources {
        cpu    = 100
        memory = 256
      }
    }
%{ endif ~}
  }
}
```

Key changes from the single-node version:
- Job name is `${servicename}` (not hardcoded `mongodb`)
- Node constraint pins to `${node_name}`
- CSI volume `${servicename}-data` replaces CephFS bind mounts for `/data/db`
- CephFS `/data/configdb` mount removed (configdb goes in the CSI volume alongside data)
- Keyfile stays as CephFS bind mount (shared, read-only)
- `connect { native = true }` removed (not needed for replica set)
- Homepage tags only on primary (`is_primary` conditional)
- Memory bumped to 1024 MB
- `rs-init` poststart task only on `mongodb-1`
- `rs-init` uses `MONGOSH_PASSWORD` env var (avoids password in process args)
- 5-second sleep before init to let mongod finish starting

**Step 2: Validate the Terraform module**

Run: `terraform validate`
Expected: Success

**Step 3: Run terraform plan (dry run)**

Run: `terraform plan`

Expected: Plan shows 3 new `nomad_job.mongodb` resources (one per member). The old single `nomad_job.mongodb` (without index) will be destroyed since the resource address changed from `nomad_job.mongodb` to `nomad_job.mongodb["mongodb-1"]` etc.

Review the plan carefully. The old `mongodb` job will be stopped. This is expected — it's a fresh start.

**Step 4: Commit**

```bash
git add terraform/mongodb/mongodb.nomad.hcl
git commit -m "feat(mongodb): 3-node replica set with CSI volumes and auto-init"
```

---

### Task 4: Update Rocket.Chat connection strings

**Files:**
- Modify: `terraform/rocketchat/variables.tf`
- Modify: `terraform/rocketchat/rocketchat.nomad.hcl`
- Modify: `terraform/rocketchat/main.tf`

**Step 1: Update `variables.tf` — replace `mongo_host` with `mongo_hosts`**

In `terraform/rocketchat/variables.tf`, replace:

```hcl
variable "mongo_host" {
  type    = string
  default = "mongodb.service.consul"
}
```

with:

```hcl
variable "mongo_hosts" {
  description = "Comma-separated MongoDB replica set hosts"
  type        = string
  default     = "mongodb-1.service.consul:27017,mongodb-2.service.consul:27017,mongodb-3.service.consul:27017"
}
```

**Step 2: Update `main.tf` — pass `mongo_hosts` instead of `mongo_host`**

In `terraform/rocketchat/main.tf`, in the `templatefile()` call, replace:

```hcl
    mongo_host   = var.mongo_host
```

with:

```hcl
    mongo_hosts  = var.mongo_hosts
```

**Step 3: Update `rocketchat.nomad.hcl` — use multi-host connection string**

In `terraform/rocketchat/rocketchat.nomad.hcl`, replace the template block:

```hcl
      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/rocketchat" }}
MONGO_URL=mongodb://{{ .mongo_username }}:{{ .mongo_password }}@${mongo_host}:27017/${mongo_db}?replicaSet=rs0&authSource=admin
MONGO_OPLOG_URL=mongodb://{{ .mongo_username }}:{{ .mongo_password }}@${mongo_host}:27017/local?replicaSet=rs0&authSource=admin
{{- end }}
EOT
      }
```

with:

```hcl
      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/rocketchat" }}
MONGO_URL=mongodb://{{ .mongo_username }}:{{ .mongo_password }}@${mongo_hosts}/${mongo_db}?replicaSet=rs0&authSource=admin
MONGO_OPLOG_URL=mongodb://{{ .mongo_username }}:{{ .mongo_password }}@${mongo_hosts}/local?replicaSet=rs0&authSource=admin
{{- end }}
EOT
      }
```

Note: `mongo_hosts` already includes `:27017` on each host, so no port suffix needed.

**Step 4: Validate**

Run: `cd ../rocketchat && terraform validate`
Expected: Success

**Step 5: Commit**

```bash
git add terraform/rocketchat/variables.tf terraform/rocketchat/main.tf terraform/rocketchat/rocketchat.nomad.hcl
git commit -m "feat(rocketchat): update connection strings for MongoDB replica set"
```

---

### Task 5: Deploy MongoDB cluster

**Prerequisite:** CSI RBD volumes `mongodb-1-data`, `mongodb-2-data`, `mongodb-3-data` must exist and be registered in Nomad.

**Step 1: Migrate Terraform state (remove old resource)**

The old `nomad_job.mongodb` (without for_each index) must be removed from state before applying, since the resource address changed:

Run: `cd terraform/mongodb && terraform state rm nomad_job.mongodb`

This only removes the state tracking — the running job stays until the new jobs are deployed.

**Step 2: Stop the old single-node MongoDB**

Run: `nomad job stop mongodb`

This stops the old `mongodb` job. Data on CephFS is preserved but won't be used (fresh start).

**Step 3: Apply the new MongoDB cluster**

Run: `terraform apply`

Expected: Creates 3 `nomad_job.mongodb` resources. Each job starts on its pinned node, pulls the mongo:8.0 image, and mounts its CSI volume.

**Step 4: Verify all 3 members are running**

Run:
```bash
nomad job status mongodb-1
nomad job status mongodb-2
nomad job status mongodb-3
```

Expected: All 3 show `Status = running` with 1 healthy allocation each.

**Step 5: Verify replica set initialized**

Check logs of the rs-init task on mongodb-1:

Run: `nomad alloc logs -task rs-init -job mongodb-1`

Expected: `Replica set initiated` or `Replica set already initialized: rs0`

**Step 6: Verify replica set status**

Run:
```bash
nomad alloc exec -task mongodb -job mongodb-1 \
  mongosh -u admin -p '<root_password>' \
  --authenticationDatabase admin --quiet \
  --eval 'rs.status().members.map(m => ({name: m.name, state: m.stateStr}))'
```

Expected:
```json
[
  { "name": "mongodb-1.service.consul:27017", "state": "PRIMARY" },
  { "name": "mongodb-2.service.consul:27017", "state": "SECONDARY" },
  { "name": "mongodb-3.service.consul:27017", "state": "SECONDARY" }
]
```

**Step 7: Commit (if any adjustments were made)**

---

### Task 6: Create Rocket.Chat database user on new cluster

**Step 1: Connect to the primary and create the rocketchat user**

Run:
```bash
nomad alloc exec -task mongodb -job mongodb-1 \
  mongosh -u admin -p '<root_password>' \
  --authenticationDatabase admin --quiet \
  --eval '
    db = db.getSiblingDB("rocketchat");
    db.createUser({
      user: "<rocketchat_username>",
      pwd: "<rocketchat_password>",
      roles: [
        { role: "readWrite", db: "rocketchat" },
        { role: "read", db: "local" }
      ]
    });
    print("Rocket.Chat user created");
  '
```

Note: Use the credentials from the existing `nomad/jobs/rocketchat` Nomad variable (same username/password as before).

**Step 2: Verify the user can authenticate**

Run:
```bash
nomad alloc exec -task mongodb -job mongodb-1 \
  mongosh -u '<rocketchat_username>' -p '<rocketchat_password>' \
  --authenticationDatabase rocketchat --quiet \
  --eval 'db.stats()'
```

Expected: Returns database stats without auth errors.

---

### Task 7: Deploy Rocket.Chat against new cluster

**Step 1: Apply Rocket.Chat changes**

Run: `cd terraform/rocketchat && terraform apply`

Expected: Updates the Nomad job with new connection strings. Rocket.Chat restarts and connects to the 3-node cluster.

**Step 2: Verify Rocket.Chat is healthy**

Run: `nomad job status rocketchat`

Expected: Deployment completed successfully, 1 healthy allocation.

**Step 3: Check logs for clean MongoDB connection**

Run: `nomad alloc logs -task rocketchat -job rocketchat | grep -i "mongodb\|version"`

Expected:
- `MongoDB Version: 8.0.19`
- No deprecation warnings
- No `ReplicaSetNoPrimary` errors
- `Connected to MongoDB database: rocketchat`

**Step 4: Verify the UI is accessible**

Open `https://rocketchat.<domain>/` in a browser. Should load the Rocket.Chat login page.

**Step 5: Commit all changes**

```bash
git add -A terraform/mongodb/ terraform/rocketchat/
git commit -m "feat(mongodb): deploy 3-node replica set with Rocket.Chat integration"
```

---

### Task 8: Failover test

**Step 1: Identify the current primary**

Run:
```bash
nomad alloc exec -task mongodb -job mongodb-1 \
  mongosh -u admin -p '<root_password>' \
  --authenticationDatabase admin --quiet \
  --eval 'rs.status().members.map(m => ({name: m.name, state: m.stateStr}))'
```

**Step 2: Stop the primary member**

If mongodb-1 is primary:

Run: `nomad job stop mongodb-1`

**Step 3: Verify automatic failover**

Wait 15 seconds, then check from mongodb-2:

Run:
```bash
nomad alloc exec -task mongodb -job mongodb-2 \
  mongosh -u admin -p '<root_password>' \
  --authenticationDatabase admin --quiet \
  --eval 'rs.status().members.map(m => ({name: m.name, state: m.stateStr}))'
```

Expected: One of mongodb-2 or mongodb-3 is now PRIMARY. mongodb-1 shows as unreachable.

**Step 4: Verify Rocket.Chat still works**

Check that Rocket.Chat remains accessible at `https://rocketchat.<domain>/`. The MongoDB driver should have automatically failed over to the new primary.

**Step 5: Restart the stopped member**

Run: `cd terraform/mongodb && terraform apply`

This re-creates the mongodb-1 job. It should rejoin the replica set as a SECONDARY.

**Step 6: Verify all 3 members healthy again**

Run the `rs.status()` check again. All 3 members should be present (1 PRIMARY, 2 SECONDARY).

---

### Task 9: Cleanup

**Step 1: Remove old CephFS MongoDB data (optional)**

The old data at `/mnt/services/mongodb/data` and `/mnt/services/mongodb/configdb` is no longer used. The keyfile at `/mnt/services/mongodb/keyfile` is still needed.

If you want to clean up:
```bash
ssh octant-01 "rm -rf /mnt/services/mongodb/data /mnt/services/mongodb/configdb"
```

**Step 2: Update inventory volumes (optional)**

Remove the old `mongodb-data` and `mongodb-configdb` host volumes from `inventory/groups.yml` if they're defined there, since data now lives on CSI RBD volumes. Keep the keyfile path.
