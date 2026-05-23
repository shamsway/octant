job "aippt" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "aippt" {
    count = 1

    network {
      port "http" {
        to = 8000
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "homepage.group=Apps",
        "homepage.name=AIPPT",
        "homepage.icon=mdi-presentation",
        "homepage.description=AI Presentation Toolkit",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/api/config"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "aippt" {
      driver = "podman"
      # Container USER is appuser; run as root in rootless agent
      # (maps to hashi UID 2000 on host) for CephFS volume access
      user = "root"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"

        # Appended to ENTRYPOINT: python aippt.py serve --host 0.0.0.0 --port 8000
        args = [
          "--db", "/app/data/slides.db",
          "--uploads-dir", "/app/uploads",
          "--gateway-config", "/app/gateway.yaml"
        ]

        volumes = [
          "/mnt/services/aippt/uploads:/app/uploads",
          "/mnt/services/aippt/images:/app/images",
          "/mnt/services/aippt/data:/app/data",
          "/mnt/services/aippt/config/models.yaml:/app/models.yaml:ro",
          "/mnt/services/aippt/config/gateway.yaml:/app/gateway.yaml:ro"
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
        TZ = "America/New_York"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/aippt" }}
ANTHROPIC_API_KEY={{ .anthropic_api_key }}
OPENAI_API_KEY={{ .openai_api_key }}
{{- end }}
EOT
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
