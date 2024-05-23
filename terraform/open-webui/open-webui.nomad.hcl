job "open-webui" {
  datacenters = ["shamsway"]
  type = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  group "open-webui" {
    network {
      port "http" {
        to = 8080
      }
      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
      }      
    }

    service {
      name = "chatllm"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.open-webui.rule=Host(`chatllm.shamsway.net`)",
        "traefik.http.routers.open-webui.entrypoints=web,websecure",
        "traefik.http.routers.open-webui.tls.certresolver=cloudflare",
        "traefik.http.routers.open-webui.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "open-webui" {
      driver = "podman"
 
      config {
        image = "docker.io/dyrnq/open-webui:main"
        #force_pull = true
        image_pull_timeout = "15m"
        ports = ["http"]
        #volumes = ["${NOMAD_TASK_DIR}/:/app/backend/data"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "open-webui"
            }
          ]
        }        
      }
 
      env {
        OLLAMA_BASE_URL="http://192.168.252.5:11434"
        WEBUI_AUTH="false"
        WEBUI_NAME="Octant LLM Chat"
        WEBUI_URL="https://chatllm.shamsway.net"
      }

      resources {
        memory = 1024
      }      
    }
  }
}