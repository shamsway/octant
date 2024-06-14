job "litellm" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }
  
  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "litellm" {

    network {
      port "http" {
        to = 4000
      }

      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
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
				"traefik.consulcatalog.connect=false",
        "traefik.http.routers.litellm.rule=Host(`litellm.shamsway.net`)",
        "traefik.http.routers.litellm.entrypoints=web,websecure",
        "traefik.http.routers.litellm.tls.certresolver=cloudflare",
      ]

      connect {
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
        image = "${image}"
        args = ["--config", "/app/config.yaml"]
        ports = ["http"]
        volumes = ["local/config.yaml:/app/config.yaml"]
        force_pull = "true"
        image_pull_timeout = "15m"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "open-webui"
            }
          ]
        }                 
      }

      volume_mount {
        volume      = "litellm"
        destination = "/app"
        read_only   = false
      }   

      template {
        destination = "$${NOMAD_TASK_DIR}/config.yaml"
        data        = <<EOT
{{- with nomadVar "nomad/jobs/litellm" -}}{{ .proxy_config }}{{- end -}}
EOT
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/litellm" -}}
LITELLM_MASTER_KEY="{{ .litellm_password }}"
UI_USERNAME="{{ .litellm_username }}"
UI_PASSWORD="{{ .litellm_password }}"
STORE_MODEL_IN_DB="True"
DATABASE_URL="postgresql://{{ .db_username }}:{{ .db_password }}@${db_server}:5432/${db_name}"
LANGFUSE_PUBLIC_KEY="{{ .langfuse_public_key }}"
LANGFUSE_SECRET_KEY="{{ .langfuse_secret_key }}"
LANGFUSE_HOST="${langfuse_url}"
# OpenAI
OPENAI_API_KEY={{ .openai_key }}
OPENAI_API_BASE=""
# Cohere
COHERE_API_KEY={{ .cohere_key }}
# OpenRouter
OR_SITE_URL = ""
OR_APP_NAME = "LiteLLM Example app"
OR_API_KEY = {{ .openrouter_key }}
# Azure API base URL
AZURE_API_BASE = ""
# Azure API version
AZURE_API_VERSION = ""
# Azure API key
AZURE_API_KEY = ""
# Replicate
REPLICATE_API_KEY = {{ .replicate_key }}
REPLICATE_API_TOKEN = ""
# Anthropic
ANTHROPIC_API_KEY = {{ .anthropic_key }}
# Groq
GROQ_API_KEY = {{ .groq_key }}
# Infisical
INFISICAL_TOKEN = ""
{{- end -}}
EOT
      }    

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}