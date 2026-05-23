# CSI RBD Test Plan — Implementation

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy Nomad CSI with Ceph RBD and validate the full volume lifecycle using a SQLite stress-test workload in the virtual cluster.

**Architecture:** Four layers — Ceph RBD pool, CSI plugin jobs (controller + node), CSI volume, test workload. Docker driver for CSI plugins (privileged), Docker for test workload. All jobs run on root agents.

**Tech Stack:** Ceph RBD, ceph-csi v3.12.2, Nomad CSI, Docker driver, Terraform, SQLite

**Design doc:** `docs/plans/2026-03-06-csi-rbd-test-plan-design.md`

---

### Task 1: Enable Docker on Root Agents

**Files:**
- Modify: `inventory/group_vars/all.yml:100` (flip `docker: false` to `docker: true`)

**Step 1: Change `docker: false` to `docker: true` in group_vars**

In `inventory/group_vars/all.yml`, line 100:

```yaml
# Before
docker: false

# After
docker: true
```

**Step 2: Run the Docker role via Ansible**

```bash
cd /home/melliott/git/octant/.worktrees/vm-deployment
ansible-playbook octant.yml -i inventory/groups.yml --tags docker -u admin --become
```

Expected: Docker installs on all 3 nodes, Docker HCL config drops into root agent config dir, root agents restart with Docker driver available.

**Step 3: Verify Docker driver is detected by Nomad**

```bash
ssh octant-01 "nomad node status -self -json" | jq '.Drivers.docker'
```

Expected: `"Detected": true, "Healthy": true`

**Step 4: Commit**

```bash
git add inventory/group_vars/all.yml
git commit -m "feat(csi): enable Docker driver on root agents for CSI plugin support"
```

---

### Task 2: Load RBD Kernel Module on All Nodes

**Files:** None (Ansible ad-hoc commands only)

**Step 1: Check if rbd module is already loaded**

```bash
ansible servers -i inventory/groups.yml -m shell -a "lsmod | grep rbd" -u admin --become
```

Expected: Likely no output (module not loaded).

**Step 2: Load the rbd module**

```bash
ansible servers -i inventory/groups.yml -m shell -a "modprobe rbd" -u admin --become
```

**Step 3: Persist across reboots**

```bash
ansible servers -i inventory/groups.yml -m shell -a "echo rbd > /etc/modules-load.d/rbd.conf" -u admin --become
```

**Step 4: Verify the module is loaded**

```bash
ansible servers -i inventory/groups.yml -m shell -a "lsmod | grep rbd" -u admin --become
```

Expected: Each node shows `rbd` in the module list.

---

### Task 3: Create Ceph RBD Pool and CSI User

**Files:** None (Ceph CLI commands via SSH)

**Step 1: Create the nomad-csi RBD pool**

```bash
ssh octant-01 "sudo ceph osd pool create nomad-csi 32"
ssh octant-01 "sudo ceph osd pool application enable nomad-csi rbd"
ssh octant-01 "sudo ceph osd pool set nomad-csi size 2"
```

**Step 2: Create a dedicated CSI user with least-privilege access**

```bash
ssh octant-01 "sudo ceph auth get-or-create client.nomad-csi \
  mon 'profile rbd' \
  osd 'profile rbd pool=nomad-csi'"
```

Expected output: `[client.nomad-csi]` with a `key = AQ...` line.

**Step 3: Extract and save the key and cluster FSID**

```bash
ssh octant-01 "sudo ceph auth get-key client.nomad-csi"
ssh octant-01 "sudo ceph fsid"
```

Save these values — they are needed in Tasks 4 and 6.

**Step 4: Verify the pool exists**

```bash
ssh octant-01 "sudo ceph osd pool ls detail | grep nomad-csi"
```

Expected: Shows `nomad-csi` pool with `size 2`, application `rbd`.

---

### Task 4: Create CSI Plugin Terraform Module

**Files:**
- Create: `terraform/ceph-csi/ceph-csi-controller.nomad.hcl`
- Create: `terraform/ceph-csi/ceph-csi-node.nomad.hcl`
- Create: `terraform/ceph-csi/main.tf`
- Create: `terraform/ceph-csi/variables.tf`

**Step 1: Create `terraform/ceph-csi/variables.tf`**

```hcl
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

variable "csi_image" {
  description = "ceph-csi container image"
  type        = string
  default     = "quay.io/cephcsi/cephcsi:v3.12.2"
}

variable "ceph_fsid" {
  description = "Ceph cluster FSID (from 'ceph fsid')"
  type        = string
}

variable "ceph_monitors" {
  description = "Ceph monitor addresses"
  type        = list(string)
  default     = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
```

**Step 2: Create `terraform/ceph-csi/ceph-csi-controller.nomad.hcl`**

```hcl
job "ceph-csi-controller" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  group "controller" {
    network {
      port "metrics" {}
    }

    task "ceph-controller" {
      driver = "docker"

      config {
        image = "${csi_image}"

        args = [
          "--type=rbd",
          "--controllerserver=true",
          "--drivername=rbd.csi.ceph.com",
          "--endpoint=unix://csi/csi.sock",
          "--nodeid=$${node.unique.name}",
          "--instanceid=$${NOMAD_ALLOC_ID}",
          "--logtostderr=true",
          "--v=5",
        ]

        volumes = [
          "./local/config.json:/etc/ceph-csi-config/config.json",
        ]

        mounts = [
          {
            type     = "tmpfs"
            target   = "/tmp/csi/keys"
            readonly = false
            tmpfs_options = {
              size = 1000000
            }
          }
        ]
      }

      template {
        data = <<-EOF
        ${ceph_config_json}
        EOF

        destination = "local/config.json"
        change_mode = "restart"
      }

      csi_plugin {
        id        = "ceph-csi"
        type      = "controller"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
```

**Step 3: Create `terraform/ceph-csi/ceph-csi-node.nomad.hcl`**

```hcl
job "ceph-csi-node" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "system"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  group "nodes" {
    network {
      port "metrics" {}
    }

    task "ceph-node" {
      driver = "docker"

      config {
        image      = "${csi_image}"
        privileged = true

        args = [
          "--type=rbd",
          "--nodeserver=true",
          "--drivername=rbd.csi.ceph.com",
          "--endpoint=unix://csi/csi.sock",
          "--nodeid=$${node.unique.name}",
          "--instanceid=$${NOMAD_ALLOC_ID}",
          "--logtostderr=true",
          "--v=5",
        ]

        volumes = [
          "./local/config.json:/etc/ceph-csi-config/config.json",
        ]

        mounts = [
          {
            type     = "tmpfs"
            target   = "/tmp/csi/keys"
            readonly = false
            tmpfs_options = {
              size = 1000000
            }
          },
          {
            type     = "bind"
            target   = "/dev"
            source   = "/dev"
            readonly = false
          },
          {
            type     = "bind"
            target   = "/sys"
            source   = "/sys"
            readonly = true
          },
          {
            type     = "bind"
            target   = "/lib/modules"
            source   = "/lib/modules"
            readonly = true
          },
        ]
      }

      template {
        data = <<-EOF
        ${ceph_config_json}
        EOF

        destination = "local/config.json"
        change_mode = "restart"
      }

      csi_plugin {
        id        = "ceph-csi"
        type      = "node"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
```

**Step 4: Create `terraform/ceph-csi/main.tf`**

```hcl
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

locals {
  ceph_config_json = jsonencode([{
    clusterID = var.ceph_fsid
    monitors  = var.ceph_monitors
  }])
}

resource "nomad_job" "ceph_csi_controller" {
  jobspec = templatefile("${path.module}/ceph-csi-controller.nomad.hcl", {
    region           = var.region
    datacenter       = var.datacenter
    csi_image        = var.csi_image
    ceph_config_json = local.ceph_config_json
  })
}

resource "nomad_job" "ceph_csi_node" {
  jobspec = templatefile("${path.module}/ceph-csi-node.nomad.hcl", {
    region           = var.region
    datacenter       = var.datacenter
    csi_image        = var.csi_image
    ceph_config_json = local.ceph_config_json
  })

  depends_on = [nomad_job.ceph_csi_controller]
}
```

**Step 5: Commit**

```bash
git add terraform/ceph-csi/
git commit -m "feat(csi): add ceph-csi controller and node plugin Terraform module"
```

---

### Task 5: Deploy CSI Plugins

**Files:** None (Terraform commands)

**Step 1: Get the Ceph FSID and create tfvars**

Create `terraform/ceph-csi/terraform.tfvars` with the FSID from Task 3:

```hcl
ceph_fsid = "<fsid from Task 3>"
```

Note: Do NOT commit this file (it may contain sensitive info). Add to `.gitignore` if needed.

**Step 2: Init and apply Terraform**

```bash
cd terraform/ceph-csi
terraform init
terraform plan
terraform apply -auto-approve
```

**Step 3: Verify plugin health**

Wait 1-2 minutes for images to pull, then:

```bash
nomad plugin status ceph-csi
```

Expected output:
```
ID        = ceph-csi
Provider  = rbd.csi.ceph.com
Controllers Healthy  = 1
Controllers Expected = 1
Nodes Healthy        = 3
Nodes Expected       = 3
```

If nodes are not all healthy, check allocation logs:

```bash
nomad alloc logs -job ceph-csi-controller -stderr
nomad alloc logs -job ceph-csi-node -stderr
```

Common issues:
- `rbd` module not loaded → go back to Task 2
- Image pull failure → check network/registry access
- Permission denied → verify `privileged = true` and Docker `allow_privileged = true`

---

### Task 6: Create CSI Test Volume and Workload Terraform Module

**Files:**
- Create: `terraform/csi-test/volume.hcl`
- Create: `terraform/csi-test/csi-test.nomad.hcl`
- Create: `terraform/csi-test/main.tf`
- Create: `terraform/csi-test/variables.tf`

**Step 1: Create `terraform/csi-test/variables.tf`**

```hcl
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

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
```

**Step 2: Create `terraform/csi-test/volume.hcl`**

This file is used manually with `nomad volume create`, not via Terraform.

Replace `<NOMAD_CSI_KEY>` and `<CEPH_FSID>` with values from Task 3.

```hcl
id        = "csi-test-vol"
name      = "csi-test-vol"
type      = "csi"
plugin_id = "ceph-csi"

capacity_min = "1GiB"
capacity_max = "5GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  userID  = "nomad-csi"
  userKey = "<NOMAD_CSI_KEY>"
}

parameters {
  clusterID     = "<CEPH_FSID>"
  pool          = "nomad-csi"
  imageFeatures = "layering"
  mkfsOptions   = "-t ext4"
}
```

**Step 3: Create `terraform/csi-test/csi-test.nomad.hcl`**

```hcl
job "csi-test" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  group "test" {
    volume "testdata" {
      type            = "csi"
      source          = "csi-test-vol"
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
    }

    network {
      port "health" {
        to = 8080
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "csi-test"
      port     = "health"
      provider = "consul"

      check {
        type     = "http"
        path     = "/health"
        name     = "csi-test-health"
        interval = "15s"
        timeout  = "5s"
      }
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "5m"
      unlimited      = true
    }

    task "sqlite-stress" {
      driver = "docker"

      volume_mount {
        volume      = "testdata"
        destination = "/data"
        read_only   = false
      }

      config {
        image   = "alpine:3.20"
        command = "/bin/sh"
        args    = ["/local/test.sh"]
        ports   = ["health"]
      }

      template {
        data = <<-SCRIPT
        #!/bin/sh
        set -e

        # Install SQLite
        apk add --no-cache sqlite busybox-extras >/dev/null 2>&1

        DB=/data/test.db
        STATUS_FILE=/tmp/status.json
        WRITE_COUNT=0
        FAIL_COUNT=0
        STARTUP_ROWS=0

        # Initialize DB
        sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS test_data (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts TEXT NOT NULL,
          payload TEXT NOT NULL,
          checksum TEXT NOT NULL
        );"

        # Count existing rows (persistence check)
        STARTUP_ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM test_data;")
        echo "=== CSI TEST: Found $STARTUP_ROWS existing rows at startup ==="

        # Start health server in background
        while true; do
          CURRENT_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM test_data;" 2>/dev/null || echo "error")
          RESPONSE="HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\",\"writes\":$WRITE_COUNT,\"failures\":$FAIL_COUNT,\"total_rows\":$CURRENT_COUNT,\"startup_rows\":$STARTUP_ROWS}"
          echo -e "$RESPONSE" | busybox-extras httpd -f -p 8080 -c /dev/null 2>/dev/null &
          break
        done

        # Actually, use a simpler approach: nc-based health server
        (while true; do
          CURRENT_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM test_data;" 2>/dev/null || echo "error")
          BODY="{\"status\":\"ok\",\"writes\":$WRITE_COUNT,\"failures\":$FAIL_COUNT,\"total_rows\":$CURRENT_COUNT,\"startup_rows\":$STARTUP_ROWS}"
          RESPONSE="HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: $${#BODY}\r\nConnection: close\r\n\r\n$$BODY"
          echo -e "$$RESPONSE" | nc -l -p 8080 -q 1 >/dev/null 2>&1 || true
        done) &

        echo "=== CSI TEST: Starting write/read/verify loop ==="

        # Main write loop
        while true; do
          TS=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
          PAYLOAD=$(head -c 64 /dev/urandom | base64)
          CHECKSUM=$(echo -n "$PAYLOAD" | sha256sum | cut -d' ' -f1)

          if sqlite3 "$DB" "PRAGMA journal_mode=WAL; INSERT INTO test_data (ts, payload, checksum) VALUES ('$TS', '$PAYLOAD', '$CHECKSUM');"; then
            # Verify the insert
            VERIFY=$(sqlite3 "$DB" "SELECT checksum FROM test_data WHERE ts='$TS' LIMIT 1;")
            if [ "$VERIFY" = "$CHECKSUM" ]; then
              WRITE_COUNT=$((WRITE_COUNT + 1))
            else
              FAIL_COUNT=$((FAIL_COUNT + 1))
              echo "VERIFY FAIL at $TS: expected=$CHECKSUM got=$VERIFY"
            fi
          else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo "WRITE FAIL at $TS"
          fi

          # Periodic integrity check and status
          if [ $((WRITE_COUNT % 100)) -eq 0 ] && [ $WRITE_COUNT -gt 0 ]; then
            INTEGRITY=$(sqlite3 "$DB" "PRAGMA integrity_check;")
            TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM test_data;")
            echo "=== CSI TEST: writes=$WRITE_COUNT fails=$FAIL_COUNT total_rows=$TOTAL integrity=$INTEGRITY ==="
          fi

          sleep 1
        done
        SCRIPT

        destination = "local/test.sh"
        perms       = "0755"
        change_mode = "restart"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
```

**Step 4: Create `terraform/csi-test/main.tf`**

```hcl
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "csi_test" {
  jobspec = templatefile("${path.module}/csi-test.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
    dns        = jsonencode(var.dns)
  })
}
```

**Step 5: Commit**

```bash
git add terraform/csi-test/
git commit -m "feat(csi): add CSI test workload with SQLite stress test"
```

---

### Task 7: Create and Verify CSI Volume

**Files:** None (Nomad CLI commands)

**Step 1: Fill in volume.hcl with real credentials**

Edit `terraform/csi-test/volume.hcl` and replace:
- `<NOMAD_CSI_KEY>` with the key from `ceph auth get-key client.nomad-csi`
- `<CEPH_FSID>` with the output of `ceph fsid`

**Step 2: Create the CSI volume**

```bash
nomad volume create terraform/csi-test/volume.hcl
```

Expected output: `Created external volume ... with ID csi-test-vol`

**Step 3: Verify volume status**

```bash
nomad volume status csi-test-vol
```

Expected: Volume shows as created, plugin ID `ceph-csi`, no allocations yet.

If volume creation fails:
- Check controller plugin logs: `nomad alloc logs -job ceph-csi-controller -stderr`
- Verify the `nomad-csi` user key is correct
- Verify the pool `nomad-csi` exists: `ssh octant-01 "sudo rbd pool stats nomad-csi"`

---

### Task 8: Deploy Test Workload and Validate (Scenario 1-2)

**Files:** None (Terraform + Nomad CLI)

**Step 1: Deploy the test workload**

```bash
cd terraform/csi-test
terraform init
terraform apply -auto-approve
```

**Step 2: Wait for job to be healthy**

```bash
nomad job status csi-test
```

Expected: Running, deployment successful. Watch for the allocation to be placed and the health check to pass.

If the allocation fails:
- Check alloc logs: `nomad alloc logs -job csi-test -stderr`
- Check volume attachment: `nomad volume status csi-test-vol`
- Common issue: Volume mount fails → check CSI node plugin logs

**Step 3: Verify writes are happening (Scenario 1: Basic Write/Read)**

```bash
nomad alloc logs -job csi-test
```

Expected: Lines like `=== CSI TEST: writes=100 fails=0 total_rows=100 integrity=ok ===`

Zero failures = PASS.

**Step 4: Verify health endpoint**

```bash
ALLOC_ID=$(nomad job status -json csi-test | jq -r '.Allocations[] | select(.ClientStatus=="running") | .ID' | head -1)
HEALTH_PORT=$(nomad alloc status -json "$ALLOC_ID" | jq -r '.Resources.Networks[0].DynamicPorts[] | select(.Label=="health") | .Value')
NODE_IP=$(nomad alloc status -json "$ALLOC_ID" | jq -r '.Resources.Networks[0].IP')
curl -s "http://$NODE_IP:$HEALTH_PORT/health" | jq .
```

Expected: JSON with `status: ok`, positive write count, zero failures.

**Step 5: Test restart persistence (Scenario 2)**

```bash
# Note the current row count
nomad alloc logs -job csi-test | tail -1

# Stop the job
nomad job stop csi-test

# Restart via Terraform
cd terraform/csi-test
terraform apply -auto-approve

# Wait for healthy, then check logs
nomad alloc logs -job csi-test | head -5
```

Expected: The first log lines should show `Found N existing rows at startup` where N matches the count before stop.

---

### Task 9: Validate Node Drain and Reattach (Scenario 3)

**Files:** None (Nomad CLI)

**Step 1: Identify current node**

```bash
ALLOC_ID=$(nomad job status -json csi-test | jq -r '.Allocations[] | select(.ClientStatus=="running") | .ID' | head -1)
NODE_ID=$(nomad alloc status -json "$ALLOC_ID" | jq -r '.NodeID')
echo "Test running on node: $NODE_ID"

# Note the current row count
nomad alloc logs -job csi-test | tail -1
```

**Step 2: Drain the node**

```bash
nomad node drain -enable -yes "$NODE_ID"
```

**Step 3: Watch for reschedule**

```bash
# Wait for new allocation on a different node
watch -n 2 'nomad job status csi-test'
```

Expected: Old allocation stops, new allocation starts on a different node.

**Step 4: Verify data survived the move**

```bash
# New allocation logs should show existing rows
nomad alloc logs -job csi-test | head -5
```

Expected: `Found N existing rows at startup` with the same count as before drain.

**Step 5: Check for orphaned attachments**

```bash
nomad volume status csi-test-vol
```

Expected: Volume shows attached to the new node only. No stale attachments to the old node.

**Step 6: Disable drain**

```bash
nomad node drain -disable "$NODE_ID"
```

**Step 7: Check RBD image state from Ceph**

```bash
ssh octant-01 "sudo rbd ls nomad-csi"
ssh octant-01 "sudo rbd info nomad-csi/<image-name>"
```

Expected: Single RBD image exists, mapped to one node.

---

### Task 10: Validate Force-Stop Recovery (Scenario 4)

**Files:** None (Nomad CLI)

**Step 1: Note current state**

```bash
nomad alloc logs -job csi-test | tail -1
ALLOC_ID=$(nomad job status -json csi-test | jq -r '.Allocations[] | select(.ClientStatus=="running") | .ID' | head -1)
```

**Step 2: Force-stop the allocation**

```bash
nomad alloc stop -f "$ALLOC_ID"
```

**Step 3: Wait for reschedule and verify**

```bash
# Watch for new allocation
watch -n 2 'nomad job status csi-test'

# Once running, check logs
nomad alloc logs -job csi-test | head -5
```

Expected: `Found N existing rows at startup` — data survived force-stop.

**Step 4: Verify volume status is clean**

```bash
nomad volume status csi-test-vol
```

Expected: Volume attached to the new allocation's node only.

---

### Task 11: Document Results and Commit

**Files:**
- Modify: `docs/plans/2026-03-06-csi-rbd-test-plan-design.md` (add results section)

**Step 1: Add a results section to the design doc**

Append to the design doc with:
- Which scenarios passed/failed
- Observed attach/detach times
- Any issues encountered and workarounds
- Whether CSI is ready for the next phase (Prometheus migration)

**Step 2: Final commit**

```bash
git add docs/plans/2026-03-06-csi-rbd-test-plan-design.md
git commit -m "docs(csi): add test results to CSI RBD test plan"
```

---

### Task 12: Cleanup (Optional, after all testing complete)

**Files:** None (CLI commands)

Only run when you're done with all testing and validation.

```bash
# Stop test workload
nomad job stop csi-test

# Delete CSI volume
nomad volume delete csi-test-vol

# Stop CSI plugins
nomad job stop ceph-csi-controller
nomad job stop ceph-csi-node

# Optionally remove the Ceph pool (destructive)
# ssh octant-01 "sudo ceph osd pool delete nomad-csi nomad-csi --yes-i-really-mean-it"

# Optionally revert Docker enablement
# Set docker: false in inventory/group_vars/all.yml
```

---

## Troubleshooting Reference

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Plugin nodes unhealthy | `rbd` module not loaded | `modprobe rbd` on the node |
| Volume create fails | Wrong FSID or user key | Re-check `ceph fsid` and `ceph auth get-key client.nomad-csi` |
| Alloc fails with `publish volume` error | CSI node plugin not running on that node | Check `nomad plugin status ceph-csi` |
| Alloc fails with `statfs ... no such file` | Volume not created or not attached | Run `nomad volume status csi-test-vol` |
| Volume stuck attached to old node | Stale attachment after crash | `nomad volume detach csi-test-vol <old-node-id>` |
| Permission denied in container | Image UID mismatch | Adjust test container to run as root (Docker default) |
| Docker driver not detected | Docker not installed or service not running | Re-run `ansible-playbook octant.yml --tags docker` |
