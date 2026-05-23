job "postgres" {
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

  group "postgres" {
    count = 1

    volume "postgres-data" {
      type            = "csi"
      source          = "postgres-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      port "postgres" {
        static = 5432
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      task     = "postgres"
      port     = "postgres"

      connect {
        native = true
      }

      tags = [
        "alloc=$${NOMAD_ALLOC_ID}",
        "homepage.group=Databases",
        "homepage.name=PostgreSQL",
        "homepage.icon=postgres",
        "homepage.description=Relational DB",
      ]

      check {
        type     = "tcp"
        port     = "postgres"
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
        volume      = "postgres-data"
        destination = "/appdata/postgres"
      }

      config {
        image   = "busybox:latest"
        command = "/bin/sh"
        args    = ["-c", "chown -R 999:999 /appdata/postgres"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "postgres" {
      driver = "docker"

      volume_mount {
        volume      = "postgres-data"
        destination = "/appdata/postgres"
        read_only   = false
      }

      config {
        image = "${image}"
        ports = ["postgres"]

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
        }
      }

      env {
        POSTGRES_DB   = "postgres"
        POSTGRES_USER = "postgres"
        PGDATA        = "/appdata/postgres/data"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/postgres" }}POSTGRES_PASSWORD={{ .postgres_password }}{{ end }}
EOT
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
