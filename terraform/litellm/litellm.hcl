job "litellm" {
  datacenters = ["shamsway"]
  type        = "service"

  group "litellm" {

    network {
        port "http" {
            static = 4000
        }
    }

    volume "litellm" {
        type      = "host"
        read_only = false
        source    = "litellm"
    }    

    task "litellm" {
      driver = "podman"

      config {
        image = "ghcr.io/berriai/litellm:main-latest"
        ports = ["http"]
      }

      volume_mount {
        volume      = "litellm"
        destination = "/app"
        read_only   = false
      }

      service {
        name = "litellm"
        provider = "consul"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.litellm.rule=Host(`litellm.shamsway.net`)",
          "traefik.http.routers.litellm.entrypoints=web,websecure",
          "traefik.http.routers.litellm.tls.certresolver=cloudflare",
          "traefik.http.routers.litellm.middlewares=redirect-web-to-websecure@internal",
        ]
        check {
          name     = "alive"
          type     = "http"
          path     = "/health/liveliness"
          interval = "10s"
          timeout  = "2s"
        }
      }      
      
      env {
        AZURE_API_KEY = "sk-123"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}