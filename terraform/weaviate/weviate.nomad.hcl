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
  default = "weaviate"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "image" {
  type = string
  default = "cr.weaviate.io/semitechnologies/weaviate:1.25.3"
}

job "weaviate" {
  datacenters = ["${var.datacenter}"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value      = true
  }

  group "weaviate" {
    network {
      port "http" {
        static = 50050
        to = 8080
      }

      port "grpc" {
        static = 50051
        to = 50051
      }

      port "metrics" {
        to = 2112
      }

      dns {
        servers = var.dns
      }
    }

    service {
      name = var.servicename
      provider = "consul"
      port = "http"
      tags   = [
        "traefik.enable=true",
        "traefik.https=true",
        "traefik.https.entrypoints=https", 
        "traefik.https.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.weaviate.rule=Host(`${var.servicename}.${var.domain}`)",
      ]

      connect {
        native = true
      }

      check {
        name      = "alive"
        type      = "http"
        path      = "/v1/.well-known/ready"
        interval  = "10s"
        timeout   = "2s"
      }      
    }

    task "weaviate" {
      driver  = "podman"

      config {
        image = var.image
        volumes = ["/mnt/services/weviate/data:/var/lib/weaviate"]
        ports = ["http","grpc","metrics"]
        logging = {
        driver = "journald"
        options = [
            {
            "tag" = "${var.servicename}"
            }
          ]
        } 
      }

      env {
        PROMETHEUS_MONITORING_ENABLED = "true"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}