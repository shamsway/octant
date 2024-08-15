variable "datacenter" {
  type = string
  default = "octant"
}

variable "servicename" {
  type = string
  default = "whoami"
}

variable "image" {
  type = string
  default = "traefik/whoami"
}

job "whoami" {
  datacenters = ["${var.datacenter}"]
  type        = "system"

  constraint {
    attribute = "${node.unique.name}"
    operator  = "regexp"
    value     = "^.*[^-][^r][^o][^o][^t]$"
  }  
  
  group "whoami" {
    count = 1

    network {
      port "http" {
        to = 80
      }
      port "https" {
        to = 443
      }      
    }

    service {
      name = var.servicename
      port = "http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${var.servicename}.rule=Host(`${var.servicename}.${var.domain}`)",
        "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",
      ]
    }

    task "server" {
      env {
        WHOAMI_PORT_NUMBER = "${NOMAD_PORT_http}"
      }

      driver = "podman"

      config {
        image = var.image
        ports = ["http"]
      }
    }
  }
}