variable "datacenter" {
  type = string
  default = "octant"
}

variable "domain" {
  type = string
  default = "octant.net"
}

variable "certresolver" {
  type = string
  default = "cloudflare"
}

job "chroma" {
  datacenters = ["${var.datacenter}"]
  type = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  group "chroma" {
    network {
      port "http" {
        static = "10000"
        to = "8000"
      }
      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
      }
    }

    service {
      name = "chroma"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.chroma.rule=Host(`chroma.${var.datacenter}`)",
        "traefik.http.routers.chroma.entrypoints=web,websecure",
        "traefik.http.routers.chroma.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.chroma.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }

      check {
        name    = "alive"
        type    = "http"
        path    = "/api/v1"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "chroma" {
      driver = "podman"

      config {
        image = "docker.io/chromadb/chroma:0.5.3"
        ports = ["http"]
        volumes = ["/mnt/services/chroma/data:/chroma/chroma"]
        logging {
          driver = "journald"
          options = [
            {
              "tag" = "chroma"
            }
          ]
        }
      }

      env {
        IS_PERSISTENT = "TRUE"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}