job "phoenix" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "phoenix" {
    network {
      port "http" {
        to = 6006
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
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "phoenix" {
      driver = "podman"
      user   = "65532"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"
        userns             = "keep-id:uid=65532,gid=65532"
        volumes = [
          "/mnt/services/phoenix/data:/data",
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
        PHOENIX_WORKING_DIR = "/data"
        PHOENIX_PORT        = "6006"
        PHOENIX_HOST        = "0.0.0.0"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/phoenix" -}}
PHOENIX_SQL_DATABASE_URL="postgresql://{{ .phoenix_db_user }}:{{ .phoenix_db_password }}@${postgres_host}:5432/${postgres_db}"
{{- end -}}
EOT
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
