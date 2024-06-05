job "open-webui" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type = "service"

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
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
        image = "${image}"
        #force_pull = true
        image_pull_timeout = "15m"
        userns = "keep-id"
        ports = ["http"]
        volumes = ["/mnt/services/open-webui/data:/app/backend/data","/mnt/services/litellm/config.yaml:/app/backend/data/litellm/config.yaml"]
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
        OLLAMA_BASE_URL="${ollama_url}"
        WEBUI_AUTH="${webui_auth}"
        WEBUI_NAME="${webui_name}"
        WEBUI_URL="${webui_url}"
      }

      template {
        destination = "secrets/env.txt"
        env = true
        data = <<EOH
{{- range service "litellm" }}OPENAI_API_BASE_URL="http://{{ .Address }}:{{ .Port }}"{{ end }}
{{ with nomadVar "nomad/jobs/open-webui" }}OPENAI_API_KEY="{{ .litellm_key }}"{{ end -}}
EOH
      }

      resources {
        memory = 1024
      }      
    }
  }
}