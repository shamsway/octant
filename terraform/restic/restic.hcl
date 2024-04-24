job "restic-backup" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  constraint {
    attribute = "${node.unique.name}"
    operator  = "regexp"
    value     = "^.*[^-][^r][^o][^o][^t]$"
  } 

  periodic {
    cron             = "0 2 * * *"
    prohibit_overlap = true
  }

  group "backup" {
    task "restic" {
      driver = "raw_exec"

      config {
        command = "local/backup.sh"
      }

      env {
        RESTIC_REPOSITORY = "${restic_repository}"
        HOSTNAME = "octant-backup"
      }
      
      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/restic-backup" }}
RESTIC_PASSWORD={{ .restic_password }}
AWS_ACCESS_KEY_ID={{ .AWS_ACCESS_KEY_ID }}
AWS_SECRET_ACCESS_KEY={{ .AWS_SECRET_ACCESS_KEY }}
{{ end }}
EOT
      }

      template {
        data = <<EOH
#!/bin/bash

echo "Repo: $RESTIC_REPOSITORY"

# Check if repo exists
restic snapshots
repo_check=$?

if [ $repo_check -eq 0 ]; then
    echo "Repository exists"
else
    echo "No repository found, running restic init"
    restic --repo "$RESTIC_REPOSITORY" init
fi

# Run the Restic backup command
restic_output=$(restic backup \
--repo "$RESTIC_REPOSITORY" --host $HOSTNAME --exclude="*.ts *.mp4" --json \
%{ for path in jsondecode(backup_volumes) ~}
"${path}" \
%{ endfor ~}
2>&1)

# Get the backup result and timestamp
backup_result=$?
backup_timestamp=$(date +"%Y-%m-%d %H:%M:%S")

# Set the result value based on the exit code
if [ $backup_result -eq 0 ]; then
  result_value="SUCCESSFUL"
  # Extract relevant information from the JSON output
  files_new=$(echo "$restic_output" | jq -r '.files_new' | awk '{sum+=$1} END {print sum}')
  files_changed=$(echo "$restic_output" | jq -r '.files_changed' | awk '{sum+=$1} END {print sum}')
  data_added=$(echo "$restic_output" | jq -r '.data_added' | awk '{sum+=$1} END {print sum}')
  total_files_processed=$(echo "$restic_output" | jq -r '.total_files_processed' | awk '{sum+=$1} END {print sum}')
  total_bytes_processed=$(echo "$restic_output" | jq -r '.total_bytes_processed' | awk '{sum+=$1} END {print sum}')
  snapshot_id=$(echo "$restic_output" | jq -r '.snapshot_id' | tail -1)  
  # Create a JSON object with the backup result and timestamp
  json_data=$(cat <<EOF
  {
    "result": "$result_value",
    "timestamp": "$backup_timestamp",
    "files_new": $files_new,
    "files_changed": $files_changed,
    "data_added": $data_added,
    "total_files_processed": $total_files_processed,
    "total_bytes_processed": $total_bytes_processed,
    "snapshot_id": "$snapshot_id"
  }
  EOF
  )

  # Store the JSON data in Consul's KV store
  curl -X PUT -d "$json_data" -H "Content-Type: application/json" "http://consul.shamsway.net:8500/v1/kv/restic/backup/nomad/$${HOSTNAME}/results"
else
  result_value="FAILED"
  json_data=$(cat <<EOF
  {
    "result": "$result_value",
    "timestamp": "$backup_timestamp"
  }
  EOF
  )
  # Store the JSON data in Consul's KV store
  curl -X PUT -d "$json_data" -H "Content-Type: application/json" "http://consul.shamsway.net:8500/v1/kv/restic/backup/nomad/$${HOSTNAME}/results"    
fi

# Print the Restic output
echo "$json_data"
echo "$restic_output"
EOH

        destination = "local/backup.sh"
        perms = "755"
      }
    }
  }
}