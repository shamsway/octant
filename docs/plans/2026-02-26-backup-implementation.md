# Backup Strategy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Set up restic backups via SFTP to the hypervisor, with Consul/Nomad snapshots and database dump jobs for Postgres and MariaDB.

**Architecture:** Restic backs up CephFS volumes directly to the hypervisor at `sftp:admin@192.168.122.1:/mnt/data/backups/lab/restic-repo`. Database dumps (pg_dumpall, mariadb-dump) land on CephFS at `/mnt/services/backups/` first, then get swept up by the restic job. Consul and Nomad state snapshots are taken inline before the restic backup runs.

**Tech Stack:** Restic, Nomad batch jobs (raw_exec), Terraform, Ansible, Consul KV for result reporting

**Reference:** `../octant-private/terraform/restic/` has the production backup script with Consul/Nomad snapshot support. The VM deployment version at `terraform/restic/` has the basic structure but needs updating.

---

### Task 1: Add backup subdirectories to volume inventory

The backup directory exists but needs subdirectories for postgres dumps, mariadb dumps, and state snapshots.

**Files:**
- Modify: `inventory/groups.yml` (volumes list, around line 72-74)

**Step 1: Add backup subdirectory volumes**

In `inventory/groups.yml`, after the existing `backups` volume entry:

```yaml
      - name: backups
        path: /mnt/services/backups
        backup: true
```

Add three new entries:

```yaml
      - name: backups-postgres
        path: /mnt/services/backups/postgres
        backup: false
      - name: backups-mariadb
        path: /mnt/services/backups/mariadb
        backup: false
      - name: backups-snapshots
        path: /mnt/services/backups/snapshots
        backup: false
```

These are `backup: false` because the parent `/mnt/services/backups` already has `backup: true` — restic will recurse into it.

**Step 2: Create directories on the cluster**

```bash
make deploy-role ROLE=volumes
```

Or manually:

```bash
ssh admin@192.168.122.101 'sudo mkdir -p /mnt/services/backups/{postgres,mariadb,snapshots} && sudo chown hashi:hashi /mnt/services/backups/{postgres,mariadb,snapshots}'
```

**Step 3: Verify**

```bash
ssh admin@192.168.122.101 'ls -la /mnt/services/backups/'
```

Expected: `postgres/`, `mariadb/`, `snapshots/` directories owned by `hashi:hashi`.

**Step 4: Commit**

```bash
git add inventory/groups.yml
git commit -m "feat(volumes): add backup subdirectories for db dumps and snapshots"
```

---

### Task 2: Set up SSH key for hashi user SFTP access

The restic Nomad job runs as `hashi` user via `raw_exec`. It needs SSH key-based access to the hypervisor at `192.168.122.1` to use the SFTP backend.

**Step 1: Generate SSH key for hashi user**

```bash
ssh admin@192.168.122.101 'sudo -u hashi ssh-keygen -t ed25519 -f /home/hashi/.ssh/id_ed25519 -N "" -C "hashi@octant-backup"'
```

**Step 2: Read the public key**

```bash
ssh admin@192.168.122.101 'sudo cat /home/hashi/.ssh/id_ed25519.pub'
```

Save this output — you'll add it to the hypervisor.

**Step 3: Add public key to hypervisor**

On the hypervisor (192.168.122.1), add the hashi public key to the admin user's authorized_keys:

```bash
echo "<paste-public-key-here>" >> ~/.ssh/authorized_keys
```

**Step 4: Create the backup destination on the hypervisor**

```bash
mkdir -p /mnt/data/backups/lab/restic-repo
```

**Step 5: Copy the SSH key to other nodes via CephFS**

Since `/home/hashi` is local to each node (not on CephFS), copy the key to all nodes:

```bash
# Read key from node 1
ssh admin@192.168.122.101 'sudo cat /home/hashi/.ssh/id_ed25519' > /tmp/hashi_key
ssh admin@192.168.122.101 'sudo cat /home/hashi/.ssh/id_ed25519.pub' > /tmp/hashi_key.pub

# Copy to node 2
ssh admin@192.168.122.102 'sudo mkdir -p /home/hashi/.ssh && sudo chmod 700 /home/hashi/.ssh && sudo chown hashi:hashi /home/hashi/.ssh'
scp /tmp/hashi_key admin@192.168.122.102:/tmp/hashi_key
scp /tmp/hashi_key.pub admin@192.168.122.102:/tmp/hashi_key.pub
ssh admin@192.168.122.102 'sudo mv /tmp/hashi_key /home/hashi/.ssh/id_ed25519 && sudo mv /tmp/hashi_key.pub /home/hashi/.ssh/id_ed25519.pub && sudo chmod 600 /home/hashi/.ssh/id_ed25519 && sudo chown -R hashi:hashi /home/hashi/.ssh'

# Copy to node 3
ssh admin@192.168.122.103 'sudo mkdir -p /home/hashi/.ssh && sudo chmod 700 /home/hashi/.ssh && sudo chown hashi:hashi /home/hashi/.ssh'
scp /tmp/hashi_key admin@192.168.122.103:/tmp/hashi_key
scp /tmp/hashi_key.pub admin@192.168.122.103:/tmp/hashi_key.pub
ssh admin@192.168.122.103 'sudo mv /tmp/hashi_key /home/hashi/.ssh/id_ed25519 && sudo mv /tmp/hashi_key.pub /home/hashi/.ssh/id_ed25519.pub && sudo chmod 600 /home/hashi/.ssh/id_ed25519 && sudo chown -R hashi:hashi /home/hashi/.ssh'

# Clean up local copies
rm /tmp/hashi_key /tmp/hashi_key.pub
```

**Step 6: Accept hypervisor host key on all nodes**

```bash
ssh admin@192.168.122.101 'sudo -u hashi ssh -o StrictHostKeyChecking=accept-new admin@192.168.122.1 "echo OK"'
ssh admin@192.168.122.102 'sudo -u hashi ssh -o StrictHostKeyChecking=accept-new admin@192.168.122.1 "echo OK"'
ssh admin@192.168.122.103 'sudo -u hashi ssh -o StrictHostKeyChecking=accept-new admin@192.168.122.1 "echo OK"'
```

Expected: each prints `OK`.

**Step 7: Verify SFTP access**

```bash
ssh admin@192.168.122.101 'sudo -u hashi sftp admin@192.168.122.1:/mnt/data/backups/lab/ <<< "ls"'
```

Expected: shows the `restic-repo` directory (or empty listing if dir just created).

---

### Task 3: Update restic repository configuration

Change the restic repo URL from the S3 placeholder to SFTP.

**Files:**
- Modify: `inventory/group_vars/all.yml:60`

**Step 1: Update the repository URL**

Change line 60 from:

```yaml
restic_repository: "s3:s3.change.me/octant-backup-bucket"
```

To:

```yaml
restic_repository: "sftp:admin@192.168.122.1:/mnt/data/backups/lab/restic-repo"
```

**Step 2: Commit**

```bash
git add inventory/group_vars/all.yml
git commit -m "feat(restic): switch backup repo from S3 placeholder to hypervisor SFTP"
```

---

### Task 4: Update restic backup script with Consul/Nomad snapshots

Port the snapshot support from `octant-private/terraform/restic/backup.sh.tmpl` into the VM deployment version. The script is templated by Terraform and stored as a Nomad variable.

**Files:**
- Modify: `terraform/restic/backup.sh.tmpl`

**Step 1: Replace backup.sh.tmpl**

Replace the contents of `terraform/restic/backup.sh.tmpl` with this updated version that adds Consul/Nomad snapshots, path validation, and better error handling. Adapted from the octant-private version but simplified for the VM lab (no parameterized dispatch, no BACKUP_TYPE):

```bash
#!/bin/bash
set -e

echo "Repo: $RESTIC_REPOSITORY"
echo "Hostname: $HOSTNAME"

# Check if repo exists, init if needed
if ! restic cat config >/dev/null 2>&1; then
    echo "No repository found, running restic init"
    restic init || { echo "ERROR: Failed to initialize repository"; exit 1; }
fi

# --- Consul & Nomad Snapshots ---
SNAP_DIR="/mnt/services/backups/snapshots"
mkdir -p "$SNAP_DIR"
timestamp=$(date +%Y%m%d_%H%M%S)

echo "Creating Consul snapshot..."
if consul snapshot save "$SNAP_DIR/consul_$timestamp.snap"; then
    echo "Consul snapshot saved"
    # Keep only last 7 snapshots
    ls -t "$SNAP_DIR"/consul_*.snap 2>/dev/null | tail -n +8 | xargs -r rm
else
    echo "WARNING: Consul snapshot failed (continuing with backup)"
fi

echo "Creating Nomad snapshot..."
if nomad operator snapshot save "$SNAP_DIR/nomad_$timestamp.snap"; then
    echo "Nomad snapshot saved"
    ls -t "$SNAP_DIR"/nomad_*.snap 2>/dev/null | tail -n +8 | xargs -r rm
else
    echo "WARNING: Nomad snapshot failed (continuing with backup)"
fi

# --- Build backup paths, skip non-existent ---
backup_paths=()
%{ for path in jsondecode(backup_volumes) ~}
if [ -e "${path}" ]; then
    backup_paths+=("${path}")
else
    echo "Skipping non-existent path: ${path}"
fi
%{ endfor ~}

if [ $${#backup_paths[@]} -eq 0 ]; then
    echo "ERROR: No valid backup paths found"
    exit 1
fi

echo "Backing up $${#backup_paths[@]} paths..."

# --- Run restic backup ---
restic_output=$(restic backup \
    --repo "$RESTIC_REPOSITORY" --host $HOSTNAME \
    --exclude="*.ts *.mp4" --json \
    "$${backup_paths[@]}" 2>&1)

backup_result=$?
backup_timestamp=$(date +"%Y-%m-%d %H:%M:%S")

if [ $backup_result -eq 0 ]; then
    result_value="SUCCESSFUL"
    files_new=$(echo "$restic_output" | jq -r '.files_new' | awk '{sum+=$1} END {print sum}')
    files_changed=$(echo "$restic_output" | jq -r '.files_changed' | awk '{sum+=$1} END {print sum}')
    data_added=$(echo "$restic_output" | jq -r '.data_added' | awk '{sum+=$1} END {print sum}')
    total_files_processed=$(echo "$restic_output" | jq -r '.total_files_processed' | awk '{sum+=$1} END {print sum}')
    total_bytes_processed=$(echo "$restic_output" | jq -r '.total_bytes_processed' | awk '{sum+=$1} END {print sum}')
    snapshot_id=$(echo "$restic_output" | jq -r '.snapshot_id' | tail -1)

    # Prune old backups
    echo "Pruning old backups..."
    restic forget --repo "$RESTIC_REPOSITORY" --host $HOSTNAME --prune --keep-daily 180

    json_data=$(cat <<EOF
{
  "result": "$result_value",
  "timestamp": "$backup_timestamp",
  "files_new": $files_new,
  "files_changed": $files_changed,
  "data_added": $data_added,
  "total_files_processed": $total_files_processed,
  "total_bytes_processed": $total_bytes_processed,
  "snapshot_id": "$snapshot_id",
  "consul_snapshot": "included",
  "nomad_snapshot": "included",
  "paths_processed": $${#backup_paths[@]}
}
EOF
    )
else
    result_value="FAILED"
    json_data=$(cat <<EOF
{
  "result": "$result_value",
  "timestamp": "$backup_timestamp"
}
EOF
    )
fi

# Store results in Consul KV
curl -s -f -X PUT -d "$json_data" -H "Content-Type: application/json" \
    "http://consul.service.consul:8500/v1/kv/restic/backup/nomad/$${HOSTNAME}/results" || \
    echo "WARNING: Failed to store results in Consul KV"

echo "$json_data"
echo "$restic_output"
```

**Step 2: Update restic.nomad.hcl to remove AWS requirement for SFTP**

The SFTP backend doesn't need AWS credentials. Update `terraform/restic/restic.nomad.hcl` env block — keep the variables but make them optional by providing defaults in the template:

```hcl
      env {
        RESTIC_REPOSITORY = "${restic_repository}"
        HOSTNAME = "octant-backup"
      }
```

No change needed here — the env block doesn't reference AWS vars directly. They're injected via the Nomad variable template. The template still renders them but restic ignores them for SFTP.

**Step 3: Update terraform/restic/main.tf**

The current `main.tf` references `api_backblaze_creds` from 1Password, which may not exist. Make AWS credentials optional by providing fallback values. Replace the `data "onepassword_item" "backblaze"` block and the `nomad_variable` resource:

In `terraform/restic/main.tf`, change the `nomad_variable` resources. The current code has two conflicting `nomad_variable` resources writing to the same path. Consolidate into one:

```hcl
resource "nomad_variable" "restic_backup" {
  path = "nomad/jobs/restic-backup"
  items = {
    backup_script         = data.template_file.restic_backup_script.rendered
    restic_password       = data.onepassword_item.restic_pass.password
    AWS_ACCESS_KEY_ID     = "unused-sftp"
    AWS_SECRET_ACCESS_KEY = "unused-sftp"
  }
}
```

Remove:
- `data "onepassword_item" "backblaze"` block (line 36-39)
- `resource "nomad_variable" "restic_password"` block (line 85-92) — consolidated above
- `resource "nomad_variable" "restic_backup_script"` block (line 60-65) — consolidated above

Also update the `data "template_file" "restic_job"` to use `local.restic_repository` without the `/nfs` suffix (line 74):

```hcl
    restic_repository = local.restic_repository
```

Remove the `api_backblaze_creds` optional item from `roles/seed-onepassword/defaults/main.yml` if desired (or leave it — it's in the optional list so it just logs a message).

**Step 4: Remove unused variables from terraform/restic/variables.tf**

Remove these variable declarations (they're no longer used since we hardcode placeholder AWS values):

```hcl
variable "restic_password" { ... }
variable "AWS_ACCESS_KEY_ID" { ... }
variable "AWS_SECRET_ACCESS_KEY" { ... }
```

**Step 5: Commit**

```bash
git add terraform/restic/
git commit -m "feat(restic): add Consul/Nomad snapshots and switch to SFTP backend"
```

---

### Task 5: Deploy and verify restic backup

**Step 1: Initialize and apply**

```bash
cd terraform/restic && terraform init -upgrade && terraform apply -auto-approve
```

**Step 2: Verify the Nomad job is registered**

```bash
ssh admin@192.168.122.101 'nomad job status restic-backup'
```

Expected: Shows `restic-backup` job with `periodic` status, scheduled at `0 2 * * *`.

**Step 3: Force a test run**

```bash
ssh admin@192.168.122.101 'nomad job periodic force restic-backup'
```

**Step 4: Wait ~30s, then check the dispatch**

```bash
ssh admin@192.168.122.101 'nomad job status restic-backup | tail -20'
```

Look for a dispatched child job. Check its logs:

```bash
ssh admin@192.168.122.101 'ALLOC=$(nomad job status restic-backup 2>/dev/null | grep -E "run|complete" | tail -1 | awk "{print \$1}"); nomad alloc logs "$ALLOC" 2>&1 | tail -30'
```

Expected: Shows backup running, Consul/Nomad snapshots taken, paths backed up, result stored in Consul KV.

**Step 5: Verify backup on hypervisor**

On the hypervisor:

```bash
ls -la /mnt/data/backups/lab/restic-repo/
```

Expected: restic repository files (config, data/, index/, keys/, snapshots/).

**Step 6: Verify Consul KV result**

```bash
ssh admin@192.168.122.101 'curl -s http://consul.service.consul:8500/v1/kv/restic/backup/nomad/octant-backup/results?raw'
```

Expected: JSON with `"result": "SUCCESSFUL"`.

---

### Task 6: Fix and deploy postgres-backup job

The postgres-backup terraform module exists but has never been applied in the VM lab.

**Files:**
- Modify: `terraform/postgres-backup/variables.tf` (fix defaults for VM lab)
- Modify: `terraform/postgres-backup/main.tf` (add 1Password integration for postgres password)

**Step 1: Update variables.tf defaults**

The current defaults point to `nomad.octant.net` and `consul.octant.net` (production). Change to `localhost`:

```hcl
variable "nomad" {
  description = "Nomad server address"
  type    = string
  default = "localhost"
}

variable "consul" {
  description = "Consul server address"
  type    = string
  default = "localhost"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}
```

**Step 2: Add 1Password integration to main.tf**

The postgres-backup job needs the postgres password stored in a Nomad variable. Add 1Password provider and create the Nomad variable. Replace `terraform/postgres-backup/main.tf`:

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

provider "consul" {
  address = "http://${var.consul}:8500"
}

provider "onepassword" {}

data "onepassword_vault" "vault" {
  name = "Octant"
}

data "onepassword_item" "postgres" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_postgres"
}

data "nomad_allocations" "postgres" {
  filter = "Name == \"postgres.db[0]\" and ClientStatus == \"running\""
}

resource "consul_keys" "postgres_alloc" {
  key {
    path  = "service/postgres/alloc"
    value = data.nomad_allocations.postgres.allocations[0].id
  }
}

resource "nomad_variable" "postgres_backup" {
  path = "nomad/jobs/postgres-backup"
  items = {
    postgres_password = data.onepassword_item.postgres.password
  }
}

resource "nomad_job" "postgres_backup" {
  depends_on = [consul_keys.postgres_alloc, nomad_variable.postgres_backup]
  jobspec    = templatefile("${path.module}/postgres-backup.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
  })
}
```

**Step 3: Initialize and apply**

```bash
cd terraform/postgres-backup && terraform init -upgrade && terraform apply -auto-approve
```

**Step 4: Verify the job is registered**

```bash
ssh admin@192.168.122.101 'nomad job status postgres-backup'
```

Expected: Periodic batch job, scheduled at `30 4 * * *`.

**Step 5: Force a test run**

```bash
ssh admin@192.168.122.101 'nomad job periodic force postgres-backup'
```

Wait ~10s, then check:

```bash
ssh admin@192.168.122.101 'ls -la /mnt/services/backups/postgres/'
```

Expected: A `postgres_backup_YYYYMMDD_HHMMSS.sql.gz` file.

**Step 6: Commit**

```bash
git add terraform/postgres-backup/
git commit -m "fix(postgres-backup): update defaults for VM lab and add 1Password integration"
```

---

### Task 7: Create MariaDB backup job

Mirror the postgres-backup pattern for MariaDB.

**Files:**
- Create: `terraform/mariadb-backup/main.tf`
- Create: `terraform/mariadb-backup/variables.tf`
- Create: `terraform/mariadb-backup/mariadb-backup.nomad.hcl`

**Step 1: Create variables.tf**

Create `terraform/mariadb-backup/variables.tf`:

```hcl
variable "nomad" {
  description = "Nomad server address"
  type    = string
  default = "localhost"
}

variable "consul" {
  description = "Consul server address"
  type    = string
  default = "localhost"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}
```

**Step 2: Create mariadb-backup.nomad.hcl**

Create `terraform/mariadb-backup/mariadb-backup.nomad.hcl`:

```hcl
job "mariadb-backup" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  periodic {
    crons            = ["0 4 * * *"]
    prohibit_overlap = true
  }

  task "mariadb-backup" {
    driver = "raw_exec"

    config {
      command = "/bin/sh"
      args    = ["-c", "local/mariadb_backup.sh"]
    }

    template {
      destination = "$${NOMAD_SECRETS_DIR}/env.txt"
      env         = true
      data        = <<EOT
{{ with nomadVar "nomad/jobs/mariadb" }}MYSQL_ROOT_PASSWORD={{ .root_password }}{{ end }}
DB_ALLOC_ID={{ key "service/mariadb/alloc" }}
EOT
    }

    template {
      destination = "local/mariadb_backup.sh"
      env         = false
      perms       = "755"
      data        = <<EOT
timestamp=$(date +%Y%m%d_%H%M%S)
echo "Starting MariaDB backup at $timestamp"
nomad alloc exec -task mariadb $DB_ALLOC_ID /bin/bash -c "mariadb-dump -u root -p'$MYSQL_ROOT_PASSWORD' --all-databases" | gzip -9 -c > /mnt/services/backups/mariadb/mariadb_backup_$timestamp.sql.gz
result=$?
if [ $result -eq 0 ]; then
    echo "MariaDB backup successful: /mnt/services/backups/mariadb/mariadb_backup_$timestamp.sql.gz"
    ls -lh /mnt/services/backups/mariadb/mariadb_backup_$timestamp.sql.gz
else
    echo "ERROR: MariaDB backup failed with exit code $result"
    exit 1
fi
echo "Cleaning up backups older than 30 days..."
find /mnt/services/backups/mariadb/ -type f -name "mariadb_backup_*.sql.gz" -mtime +30 -delete
echo "MariaDB backup complete"
EOT
    }
  }
}
```

**Step 3: Create main.tf**

Create `terraform/mariadb-backup/main.tf`:

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

provider "consul" {
  address = "http://${var.consul}:8500"
}

provider "onepassword" {}

data "nomad_allocations" "mariadb" {
  filter = "Name == \"mariadb.mariadb[0]\" and ClientStatus == \"running\""
}

resource "consul_keys" "mariadb_alloc" {
  key {
    path  = "service/mariadb/alloc"
    value = data.nomad_allocations.mariadb.allocations[0].id
  }
}

resource "nomad_job" "mariadb_backup" {
  depends_on = [consul_keys.mariadb_alloc]
  jobspec    = templatefile("${path.module}/mariadb-backup.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
  })
}
```

Note: MariaDB root password is already stored in Nomad variable `nomad/jobs/mariadb` from the mariadb terraform module, so no additional 1Password lookup is needed here.

**Step 4: Initialize and apply**

```bash
cd terraform/mariadb-backup && terraform init && terraform apply -auto-approve
```

**Step 5: Verify job registered**

```bash
ssh admin@192.168.122.101 'nomad job status mariadb-backup'
```

Expected: Periodic batch job, scheduled at `0 4 * * *`.

**Step 6: Force a test run**

```bash
ssh admin@192.168.122.101 'nomad job periodic force mariadb-backup'
```

Wait ~10s, then check:

```bash
ssh admin@192.168.122.101 'ls -lh /mnt/services/backups/mariadb/'
```

Expected: A `mariadb_backup_YYYYMMDD_HHMMSS.sql.gz` file.

**Step 7: Commit**

```bash
git add terraform/mariadb-backup/
git commit -m "feat(mariadb-backup): add periodic MariaDB database dump job"
```

---

### Task 8: Add backup jobs to terraform execution order

Add the new backup jobs to the deployment pipeline so `make deploy-services` includes them.

**Files:**
- Modify: `inventory/group_vars/all.yml` (terraform_execution_order list, around line 138)

**Step 1: Add backup jobs to execution order**

After the `gatus` entry in `terraform_execution_order`, add the backup jobs:

```yaml
  - gatus
  # Backup jobs (run after all services are deployed)
  - postgres-backup
  - mariadb-backup
  - restic
```

**Step 2: Commit**

```bash
git add inventory/group_vars/all.yml
git commit -m "feat(deploy): add backup jobs to terraform execution order"
```

---

### Task 9: Update progress tracker

**Files:**
- Modify: `docs/plans/2026-02-21-vm-deployment-progress.md`

**Step 1: Update the current state section**

Add a bullet for backup status. Update the "Remaining Work" section to mark item 14 (backups) as done and add any new items discovered during implementation.

**Step 2: Commit**

```bash
git add docs/plans/2026-02-21-vm-deployment-progress.md
git commit -m "docs: update progress tracker with backup implementation status"
```
