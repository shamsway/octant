job "octant-backup" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  periodic {
    crons            = ["30 3 * * *"]
    prohibit_overlap = true
  }

  task "postgres-backup" {
    driver = "raw_exec"

    config {
      command = "/bin/bash"
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

  task "library-backup" {
    driver = "raw_exec"

    config {
      command = "/bin/bash"
      args = ["-c","local/library_backup.sh"]
    }

    env {
      LIBRARY_BACKUP = "/mnt/services/library/library_backup.tar"
      LIBRARY_FOLDERS = "/mnt/services/library/movies /mnt/services/library/tvshows"
      LIBRARY_BACKUP_FOLDER = "/mnt/services/backups/library"
    }

    template {
      destination = "local/library_backup.sh"
      env         = false
      perms       = "755"        
      data        = <<EOT
# Create or update library TAR
if [ -f "$LIBRARY_BACKUP" ]; then
    echo "Performing incremental backup..."
    tar -uvf "$LIBRARY_BACKUP" "$LIBRARY_FOLDERS"
else
    echo "Creating initial full backup..."
    tar -cvf "$LIBRARY_BACKUP" "$LIBRARY_FOLDERS"
fi

# Ensure backup directory exists
[ -d "$LIBRARY_BACKUP_FOLDER" ] || mkdir -p "$LIBRARY_BACKUP_FOLDER"
timestamp=$(date +%Y%m%d_%H%M%S)
gzip -9 -cv $LIBRARY_BACKUP > $LIBRARY_BACKUP_FOLDER/library_backup_$timestamp.tar.gz

# Remove old backups
find /mnt/services/backups/library/ -type f -name "library_backup_*.tar.gz" -mtime +30 -delete
EOT
    }
  }

}