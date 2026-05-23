job "litellm" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "litellm" {

    network {
      port "http" {
        to = 4000
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
        "homepage.group=AI & LLM",
        "homepage.name=LiteLLM",
        "homepage.icon=si-openai",
        "homepage.description=LLM Proxy",
        "homepage.href=https://litellm.${domain}/ui/",
      ]

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
              "tag" = "${servicename}"
            }
          ]
        }
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
OPENAI_API_KEY={{ .openai_key }}
{{- end }}
{{ range service "phoenix" }}PHOENIX_COLLECTOR_HTTP_ENDPOINT=http://{{ .Address }}:{{ .Port }}{{ end }}
EOT
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
