job "restic-backup" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
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
{{ with nomadVar "nomad/jobs/restic-backup" }}{{ .backup_script }}{{ end }}
EOH
        destination = "local/backup.sh"
        perms = "755"
      }
    }
  }
}