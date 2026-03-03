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
