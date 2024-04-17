job "restic-backup" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  periodic {
    cron             = "0 2 * * *"
    prohibit_overlap = true
  }

  group "backup" {
    %{ for volume in jsondecode(backup_volumes) ~}
    volume "${volume.name}" {
        type      = "host"
        read_only = true
        source    = "${volume.name}"
    }
    %{ endfor ~}

    task "restic" {
      driver = "podman"

      config {
        image = "${image}"
        hostname = "octant-backup"
        args = [  
          "backup", "-v",
          "--repo", "${restic_repository}/nfs",
          %{ for volume in jsondecode(backup_volumes) ~}
          "/${volume.name}",
          %{ endfor ~}
        ]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "restic"
            }
          ]
        } 
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