job "whoami" {
  datacenters = ["shamsway"]
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
      name = "whoami"
      port = "http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.whoami.rule=Host(`whoami.shamsway.net`)",
        "traefik.http.routers.whoami.entrypoints=web,websecure",
        "traefik.http.routers.whoami.tls.certresolver=cloudflare",
        "traefik.http.routers.whoami.middlewares=redirect-web-to-websecure@internal",
      ]
    }

    task "server" {
      env {
        WHOAMI_PORT_NUMBER = "${NOMAD_PORT_http}"
      }

      driver = "podman"

      config {
        image = "traefik/whoami"
        ports = ["http"]
      }
    }
  }
}