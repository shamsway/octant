job "bastionclaw" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "bastionclaw" {
    network {
      port "webui" {
        static = 13100
        to     = 3100
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "webui"

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        port     = "webui"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "orchestrator" {
      driver = "podman"

      config {
        image              = "${image}"
        force_pull         = true
        ports              = ["webui"]
        image_pull_timeout = "15m"
        volumes = [
          "${podman_socket_path}:/run/podman/podman.sock",
          "/mnt/services/bastionclaw/groups:/app/groups",
          "/mnt/services/bastionclaw/store:/app/store",
          "/mnt/services/bastionclaw/data:/app/data",
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
        DOCKER_HOST               = "unix:///run/podman/podman.sock"
        ANTHROPIC_BASE_URL        = "${litellm_base_url}"
        ANTHROPIC_MODEL           = "local/glm-5-fp8"
        CONTAINER_IMAGE           = "${agent_image}"
        WEBUI_PORT                = "3100"
        WEBUI_HOST                = "0.0.0.0"
        MAX_CONCURRENT_CONTAINERS = "3"
        TELEGRAM_ONLY             = "true"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/bastionclaw" -}}
ANTHROPIC_API_KEY="{{ .anthropic_api_key }}"
LITELLM_API_KEY="{{ .litellm_api_key }}"
{{- end -}}
EOT
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    # NOTE: qmd semantic memory sidecar removed — qmd v1.0.7 has no 'serve'
    # command. The orchestrator already runs qmd inline for indexing/search.
  }
}
