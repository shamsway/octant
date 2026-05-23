job "mariadb" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  constraint {
    attribute = "$${node.unique.name}"
    value     = "${node_name}"
  }

  group "mariadb" {
    count = 1

    volume "mariadb-data" {
      type            = "csi"
      source          = "mariadb-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

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

      tags = [
        "alloc=$${NOMAD_ALLOC_ID}",
        "homepage.group=Databases",
        "homepage.name=MariaDB",
        "homepage.icon=mariadb",
        "homepage.description=MySQL-compatible DB",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        port     = "mariadb"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "volume-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      volume_mount {
        volume      = "mariadb-data"
        destination = "/var/lib/mysql"
      }

      config {
        image   = "busybox:latest"
        command = "/bin/sh"
        args    = ["-c", "chown -R 999:999 /var/lib/mysql"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "mariadb" {
      driver = "docker"
      user   = "mysql"

      volume_mount {
        volume      = "mariadb-data"
        destination = "/var/lib/mysql"
      }

      config {
        image = "${image}"
        ports = ["mariadb"]

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
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
