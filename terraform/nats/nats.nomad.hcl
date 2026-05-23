job "nats" {
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

  group "nats" {
    count = 1

    network {
      port "client" {
        to = 4222
      }

      port "monitoring" {
        to = 8222
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "client"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=false",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }

    service {
      name     = "${servicename}-monitoring"
      provider = "consul"
      port     = "monitoring"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}-monitoring.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}-monitoring.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}-monitoring.tls.certresolver=${certresolver}",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/healthz"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "nats" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["client", "monitoring"]

        args = [
          "--jetstream",
          "--store_dir", "/data/jetstream",
          "--http_port", "8222",
        ]

        volumes = [
          "/mnt/services/nats/data:/data/jetstream"
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

      env {
        TZ = "America/New_York"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
