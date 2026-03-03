job "graphiti" {
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

  group "graphiti" {
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
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/healthcheck"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "graphiti" {
      driver = "podman"
      # Image installs uv in /root/.local/bin/ but sets USER app — override to root
      user = "root"
      config {
        image = "${image}"
        ports = ["http"]

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
        TZ              = "America/New_York"
        OPENAI_BASE_URL = "http://litellm.service.consul:4000/v1"
        NEO4J_USER      = "neo4j"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/litellm" }}
OPENAI_API_KEY={{ .litellm_password }}
{{- end }}
{{- with nomadVar "nomad/jobs/neo4j" }}
NEO4J_PASSWORD={{ .NEO4J_PASSWORD }}
{{- end }}
{{ range service "neo4j-bolt" -}}
NEO4J_URI=bolt://{{ .Address }}:{{ .Port }}
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
