  # terraform apply -auto-approve
  # terraform destroy -auto-approve

job "mariadb" {
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

  group "mariadb" {
    count = 1

    network {
      port "mariadb" {
        static = 3306
        to     = 3306
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      task     = "mariadb"
      port     = "mariadb"

      connect {
        native = true
      }

      tags = ["alloc=$${NOMAD_ALLOC_ID}"]

      check {
        name     = "alive"
        type     = "tcp"
        port     = "mariadb"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "mariadb" {
      driver = "podman"
      user   = "mysql"

      config {
        image              = "${image}"
        userns             = "keep-id:uid=999,gid=999"
        ports              = ["mariadb"]
        image_pull_timeout = "15m"
        volumes = [
          "/mnt/services/mariadb/data:/var/lib/mysql",
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

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/mariadb" }}MYSQL_ROOT_PASSWORD={{ .root_password }}{{ end }}
EOT
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
