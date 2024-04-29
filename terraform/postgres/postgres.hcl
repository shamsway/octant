# terraform apply -auto-approve
# terraform destroy -auto-approve

job "postgres" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  meta {
    version = "1"
  }

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "db" {
    count = 1

    network {
      port "postgres" {
        static = 5432
      }
    }

    volume "postgres-data" {
      type      = "host"
      read_only = false
      source    = "postgres-data"
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    service {
      name = "postgres"
      provider = "consul"        
      port = "postgres"
      connect {
        native = true
      }

      check {
        type     = "tcp"
        port     = "postgres"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "postgres" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["postgres"]
        userns = "keep-id:uid=70,gid=70"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "postgres"
            }
          ]
        } 
      }

      volume_mount {
        volume      = "postgres-data"
        destination = "/appdata/postgres"
        read_only   = false
      }

      env {
        POSTGRES_DB       = "postgres"
        POSTGRES_USER     = "postgres"
        POSTGRES_PASSWORD = "${postgres_password}"
        PGDATA            = "/appdata/postgres"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
