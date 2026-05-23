# MongoDB Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy MongoDB 7 as a shared infrastructure service on the Octant homelab, with replica set mode enabled for downstream apps.

**Architecture:** Single `mongo:7` container running in replica set mode (`--replSet rs0`) on a rootless Nomad agent. Auth via 1Password → Nomad variables. Static port 27017 registered in Consul. Manual `rs.initiate()` post-deploy.

**Tech Stack:** Terraform, Nomad (Podman driver), Consul, 1Password, CephFS

**Reference files:**
- Pattern to follow: `terraform/mariadb/` (closest existing database deployment)
- Design doc: `docs/plans/2026-03-03-mongodb-deployment-design.md`
- Volumes skill: `~/.claude/plugins/marketplaces/shamsway-plugins/plugins/octant-volumes/SKILL.md`
- Secrets skill: `~/.claude/plugins/marketplaces/shamsway-plugins/plugins/octant-secrets-management/SKILL.md`

---

### Task 1: Create 1Password Secret

**Files:**
- None (external system)

**Step 1: Verify op CLI authentication**

Run: `op whoami`
Expected: Shows account info without error.

**Step 2: Check if secret already exists**

Run: `op item get service_mongodb --vault Octant 2>/dev/null && echo "EXISTS" || echo "MISSING"`
Expected: `MISSING`

**Step 3: Create the service_mongodb secret**

Run:
```bash
op item create \
  --category login \
  --title "service_mongodb" \
  --vault Octant \
  --generate-password=32,letters,digits \
  username=admin
```
Expected: Item created with auto-generated password.

**Step 4: Verify the secret**

Run: `op item get service_mongodb --vault Octant --fields username,password`
Expected: Shows `admin` username and a 32-char password.

---

### Task 2: Add Volumes to Inventory

**Files:**
- Modify: `inventory/groups.yml` (append after line 243, the `neo4j-logs` entry)

**Step 1: Add mongodb volume entries**

Add these entries at the end of the `volumes:` list in `inventory/groups.yml`:

```yaml
      - name: mongodb-data
        path: /mnt/services/mongodb/data
        backup: true
      - name: mongodb-configdb
        path: /mnt/services/mongodb/configdb
        backup: true
```

**Step 2: Run volume creation playbook**

Run:
```bash
ansible-playbook playbooks/05-deploy-volumes.yml \
  -i inventory/provisioned_vms.yml -i inventory/groups.yml
```
Expected: Tasks show "changed" for new mongodb directories.

**Step 3: Verify volumes exist**

Run: `ls -la /mnt/services/mongodb/`
Expected: Shows `data/` and `configdb/` directories owned by `hashi:hashi` with `0755` permissions.

**Step 4: Commit**

```bash
git add inventory/groups.yml
git commit -m "feat(mongodb): add CephFS volumes for MongoDB data and config"
```

---

### Task 3: Create Terraform Variable Definitions

**Files:**
- Create: `terraform/mongodb/variables.tf`

**Step 1: Create the terraform/mongodb directory**

Run: `mkdir -p terraform/mongodb`

**Step 2: Write variables.tf**

Create `terraform/mongodb/variables.tf` with standard lab defaults:

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
  default = "docker.io/mongo:7"
}

variable "servicename" {
  type    = string
  default = "mongodb"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
```

Note: No `domain` or `certresolver` variables — MongoDB is a database service with no Traefik routing.

---

### Task 4: Create Terraform Main Configuration

**Files:**
- Create: `terraform/mongodb/main.tf`

**Step 1: Write main.tf**

Create `terraform/mongodb/main.tf` following the MariaDB pattern:

```hcl
terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
    }
  }
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
    root_username = data.onepassword_item.mongodb_root.username
    root_password = data.onepassword_item.mongodb_root.password
  }
}

resource "nomad_job" "mongodb" {
  jobspec = templatefile("${path.module}/mongodb.nomad.hcl", {
    region      = var.region
    datacenter  = var.datacenter
    image       = var.image
    dns         = jsonencode(var.dns)
    servicename = var.servicename
  })
  depends_on = [nomad_variable.mongodb]
}
```

---

### Task 5: Create Nomad Job Specification

**Files:**
- Create: `terraform/mongodb/mongodb.nomad.hcl`

**Step 1: Write the Nomad job spec**

Create `terraform/mongodb/mongodb.nomad.hcl`:

```hcl
job "mongodb" {
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

  group "mongodb" {
    count = 1

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

      connect {
        native = true
      }

      tags = ["alloc=$${NOMAD_ALLOC_ID}"]

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

      config {
        image              = "${image}"
        ports              = ["mongodb"]
        image_pull_timeout = "15m"

        args = [
          "mongod",
          "--replSet", "rs0",
          "--oplogSize", "128",
          "--bind_ip_all"
        ]

        volumes = [
          "/mnt/services/mongodb/data:/data/db",
          "/mnt/services/mongodb/configdb:/data/configdb"
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
        memory = 512
      }
    }
  }
}
```

Key decisions:
- `args` includes `mongod --replSet rs0 --oplogSize 128 --bind_ip_all` for replica set mode
- TCP health check on port 27017 (consistent with other databases)
- No `userns` mapping — mongo:7 runs as root by default, which maps to hashi user in rootless mode
- `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` injected via Nomad variables template
- `--bind_ip_all` allows connections from Consul health checks and other containers

---

### Task 6: Validate Configuration

**Files:**
- Validate: `terraform/mongodb/mongodb.nomad.hcl`, `terraform/mongodb/main.tf`, `terraform/mongodb/variables.tf`

**Step 1: Format the Nomad job spec**

Run: `nomad fmt terraform/mongodb/mongodb.nomad.hcl`
Expected: File formatted (or already formatted).

**Step 2: Initialize Terraform**

Run: `cd terraform/mongodb && terraform init`
Expected: Providers downloaded, backend initialized.

**Step 3: Validate Terraform config**

Run: `terraform validate`
Expected: `Success! The configuration is valid.`

**Step 4: Plan the deployment**

Run: `terraform plan`
Expected: Shows 2 resources to create (`nomad_variable.mongodb`, `nomad_job.mongodb`). No errors.

**Step 5: Commit all terraform files**

```bash
git add terraform/mongodb/
git commit -m "feat(mongodb): add Nomad job and Terraform config for MongoDB 7"
```

---

### Task 7: Deploy MongoDB

**Step 1: Apply Terraform**

Run: `cd terraform/mongodb && terraform apply -auto-approve`
Expected: 2 resources created successfully.

**Step 2: Verify Nomad job is running**

Run: `nomad job status mongodb`
Expected: Status `running`, one healthy allocation.

**Step 3: Verify Consul registration**

Run: `consul catalog services | grep mongodb`
Expected: `mongodb` listed.

**Step 4: Check container logs for startup**

Run: `nomad alloc logs -job mongodb`
Expected: MongoDB startup messages, listening on port 27017. May show replica set "not yet initialized" warning — that's expected.

---

### Task 8: Initialize Replica Set

**Step 1: Initialize the replica set**

Run:
```bash
nomad alloc exec -job mongodb mongosh --eval \
  "rs.initiate({_id:'rs0', members:[{_id:0, host:'localhost:27017'}]})"
```
Expected: `{ ok: 1 }` — replica set initialized.

**Step 2: Verify replica set status**

Run: `nomad alloc exec -job mongodb mongosh --eval "rs.status()"`
Expected: Shows one member with `stateStr: "PRIMARY"`.

**Step 3: Verify authenticated access works**

Run:
```bash
nomad alloc exec -job mongodb mongosh \
  --username admin --password "$(op read 'op://Octant/service_mongodb/password')" \
  --eval "db.adminCommand('ping')"
```
Expected: `{ ok: 1 }`

**Step 4: Final health check verification**

Run: `consul health state critical | grep mongodb`
Expected: No output (no critical checks — TCP health check passing).

---

### Task 9: Final Commit and Cleanup

**Step 1: Verify everything is green**

Run:
```bash
nomad job status mongodb
consul catalog services | grep mongodb
```
Expected: Job running, service registered.

**Step 2: Commit any remaining changes**

If any files were modified during deployment (e.g., terraform state), commit them.

**Step 3: Update the autodeploy candidates doc**

In `docs/plans/2026-02-27-autodeploy-candidates-design.md`, add a deployment status note to the MongoDB section (I1) indicating it has been deployed.
