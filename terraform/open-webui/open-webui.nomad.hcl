job "open-webui" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type = "service"
  
  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "open-webui" {
    network {
      port "http" {
        to = 8080
      }
      dns {
        servers = ${dns}
      }      
    }

    service {
      name = "${servicename}"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
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
        force_pull = true
        image_pull_timeout = "15m"
        ports = ["http"]
        volumes = ["/mnt/services/open-webui/data:/app/backend/data","/mnt/services/litellm/config.yaml:/app/backend/data/litellm/config.yaml"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
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