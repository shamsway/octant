job "litellm" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }
  
  group "litellm" {

    network {
        port "http" {
            to = 4000
        }
    }

    volume "litellm" {
        type      = "host"
        read_only = false
        source    = "litellm"
    }    

    service {
      name = "litellm"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
				"traefik.consulcatalog.connect=true",
        "traefik.http.routers.litellm.rule=Host(`litellm.shamsway.net`)",
        "traefik.http.routers.litellm.entrypoints=web,websecure",
        "traefik.http.routers.litellm.tls.certresolver=cloudflare",
        "traefik.http.services.litellm.loadbalancer.server.port=${NOMAD_HOST_PORT_http}"
      ]

      connect {
        #sidecar_service { }
        native = true
      }        

      check {
        name     = "alive"
        type     = "http"
        path     = "/health/liveliness"
        interval = "60s"
        timeout  = "5s"
      }
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