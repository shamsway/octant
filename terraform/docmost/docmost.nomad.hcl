job "docmost" {
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

  group "docmost" {
    count = 1

    network {
      port "http" {
        to = 3000
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
        "homepage.name=Docmost",
        "homepage.icon=sh-docmost",
        "homepage.description=Wiki / Docs",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "docmost" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"

        volumes = [
          "/mnt/services/docmost/storage:/app/data/storage"
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
        TZ      = "America/New_York"
        APP_URL = "https://${servicename}.${domain}"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/docmost" }}
APP_SECRET={{ .app_secret }}
DATABASE_URL=postgresql://{{ .db_user }}:{{ .db_password }}@{{ .db_host }}:{{ .db_port }}/{{ .db_name }}
REDIS_URL={{ .redis_url }}
{{- end }}
EOT
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
