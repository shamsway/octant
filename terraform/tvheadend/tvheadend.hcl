job "tvheadend" {
  datacenters = ["shamsway"]
  type        = "service"

  group "tvheadend" {
    count = 1

    volume "tvheadend-data" {
      type      = "host"
      read_only = false
      source    = "tvheadend-data"
    }

    network {
      port "http" {
        to = 9981
      }
    }

    service {
      name = "tvheadend"
      port = "http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.tvheadend.rule=Host(`tvheadend.shamsway.net`)",
        "traefik.http.routers.tvheadend.entrypoints=web,websecure",
        "traefik.http.routers.tvheadend.tls.certresolver=cloudflare",
        "traefik.http.routers.tvheadend.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "tvheadend" {
      driver = "podman"

      config {
        image = "docker.io/linuxserver/tvheadend"
        ports = ["http"]
      }

      volume_mount {
        volume      = "tvheadend-data"
        destination = "/recordings"
        read_only   = false
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}