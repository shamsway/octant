job "postgres-backup" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  periodic {
    crons            = ["30 4 * * *"]
    prohibit_overlap = true
  }

  task "postgres-backup" {
    driver = "raw_exec"

    config {
      command = "/bin/sh"
      args = ["-c","local/postgres_backup.sh"]
    }

    env {
      POSTGRES_USER = "postgres"
    }
    
    template {
      destination = "$${NOMAD_SECRETS_DIR}/env.txt"
      env         = true
      data        = <<EOT
{{ with nomadVar "nomad/jobs/postgres-backup" }}POSTGRES_PASSWORD={{ .postgres_password }}{{ end }}
DB_ALLOC_ID={{ key "service/postgres/alloc" }}
EOT
    }

    template {
      destination = "local/postgres_backup.sh"
      env         = false
      perms       = "755"        
      data        = <<EOT
{{ with nomadVar "nomad/jobs/postgres" }}
timestamp=$(date +%Y%m%d_%H%M%S)
nomad alloc exec -task postgres $DB_ALLOC_ID /bin/bash -c "PGPASSWORD=$POSTGRES_PASSWORD PGUSER=$POSTGRES_USER /usr/bin/pg_dumpall" | gzip -9 -c > /mnt/services/backups/postgres/postgres_backup_$timestamp.sql.gz
find /mnt/services/backups/postgres/ -type f -name "postgres_backup_*.sql.gz" -mtime +30 -delete
{{ end }}
EOT
    }
  }
}