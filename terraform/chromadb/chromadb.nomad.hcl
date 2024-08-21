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

variable "servicename" {
  type = string
  default = "chroma"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
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
        servers = var.dns
      }
    }

    service {
      name = var.servicename
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${var.servicename}.rule=Host(`${var.servicename}.${var.domain}`)",
        "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",
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
              "tag" = "${var.servicename}"
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