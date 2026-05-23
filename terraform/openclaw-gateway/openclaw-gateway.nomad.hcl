job "openclaw-gateway" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "openclaw-gateway" {
    network {
      port "http" {
        to = 18789
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`openclaw.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
        "homepage.group=AI & LLM",
        "homepage.name=OpenClaw",
        "homepage.icon=si-rocket-dot-chat",
        "homepage.description=AI Agent Gateway",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        port     = "http"
        interval = "60s"
        timeout  = "5s"
      }
    }

    task "openclaw-gateway" {
      driver = "podman"

      config {
        image              = "${image}"
        force_pull         = true
        ports              = ["http"]
        image_pull_timeout = "15m"
        volumes = [
          "/mnt/services/openclaw-gateway/config:/home/node/.openclaw",
          "/mnt/services/openclaw-gateway/workspaces/scotty:/home/node/.openclaw/workspace",
          "/mnt/services/openclaw-gateway/workspaces/archivist:/home/node/.openclaw/workspaces/archivist",
          "/mnt/services/openclaw-gateway/workspaces/vec-ingest:/home/node/.openclaw/workspaces/vec-ingest",
          "/mnt/services/openclaw-gateway/workspaces/graph-ingest:/home/node/.openclaw/workspaces/graph-ingest",
          "/mnt/services/openclaw-gateway/workspaces/notes-ingest:/home/node/.openclaw/workspaces/notes-ingest",
          "/mnt/services/openclaw-gateway/workspaces/clawnerd:/home/node/.openclaw/workspaces/clawnerd",
          "/mnt/services/obsidian/vault:/mnt/services/obsidian/vault",
        ]
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
        HOME                         = "/home/node"
        OPENCLAW_GATEWAY_PORT        = "18789"
        OPENCLAW_GATEWAY_BIND        = "lan"
        CONSUL_HTTP_ADDR             = "http://consul.service.consul:8500"
        NOMAD_ADDR                   = "http://nomad.service.consul:4646"
        OTEL_SERVICE_NAME            = "openclaw-gateway"
        OTEL_EXPORTER_OTLP_ENDPOINT  = "http://otel-collector.service.consul:4327"
        OTEL_EXPORTER_OTLP_PROTOCOL  = "grpc"
        LITELLM_BASE_URL             = "${litellm_base_url}"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/openclaw-gateway" -}}
OPENCLAW_GATEWAY_TOKEN="{{ .openclaw_gateway_token }}"
ROCKETCHAT_BOT_USER="{{ .rocketchat_bot_user }}"
ROCKETCHAT_BOT_PASSWORD="{{ .rocketchat_bot_password }}"
ANTHROPIC_API_KEY="{{ .anthropic_api_key }}"
LITELLM_API_KEY="{{ .litellm_api_key }}"
{{- end -}}
EOT
      }

      resources {
        cpu    = 1024
        memory = 4096
      }
    }
  }
}
