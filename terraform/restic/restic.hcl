job "restic-backup" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  periodic {
    cron             = "0 2 * * *"
    prohibit_overlap = true
  }

  %{ for volume in backup_volumes ~}
  volume "${volume.name}" {
    type      = "host"
    read_only = true
    source    = "${volume.name}"
  }
  %{ endfor ~}

  group "backup" {
    task "restic" {
      driver = "podman"

      config {
        image = "${image}"
        args = [
          "backup",
          "--repo", "${restic_repository}",
          %{ for volume in jsondecode(backup_volumes) ~}
          "/${volume.name}",
          %{ endfor ~}
        ]
      }

      env {
        RESTIC_PASSWORD = "${restic_password}"
      }

      %{ for volume in jsondecode(backup_volumes) ~}
      volume_mount {
        volume      = "${volume.name}"
        destination = "/${volume.name}"
        read_only   = true
      }
      %{ endfor ~}
    }
  }
}