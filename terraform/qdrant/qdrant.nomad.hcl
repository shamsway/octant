job "qdrant" {
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

  group "qdrant" {
    count = 1

    network {
      port "http" {
        static = 6333
        to     = 6333
      }

      port "grpc" {
        static = 6334
        to     = 6334
      }

      port "internal" {
        static = 6335
        to     = 6335
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/healthz"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "qdrant" {
      driver = "podman"

      config {
        image              = "${image}"
        userns             = "keep-id:uid=1000,gid=1000"
        ports              = ["http", "grpc", "internal"]
        volumes            = ["/mnt/services/qdrant/data:/qdrant/storage"]
        image_pull_timeout = "15m"
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
        QDRANT__LOG_LEVEL = "INFO"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
