job "uptimekuma" {
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

  group "uptimekuma" {
    count = 1

    network {
      port "http" {
        to = 3001
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
        "homepage.group=Monitoring",
        "homepage.name=Uptime Kuma",
        "homepage.icon=uptime-kuma",
        "homepage.description=Uptime Monitoring",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "uptimekuma" {
      driver = "podman"

      config {
        image  = "${image}"
        ports  = ["http"]
        volumes = [
          "/mnt/services/uptimekuma/data:/app/data",
        ]
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

      env {
        TZ                       = "America/New_York"
        UPTIME_KUMA_DB_TYPE      = "mariadb"
        UPTIME_KUMA_DB_HOSTNAME  = "${mariadb_host}"
        UPTIME_KUMA_DB_PORT      = "3306"
        UPTIME_KUMA_DB_NAME      = "${mariadb_db}"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/uptimekuma" -}}
UPTIME_KUMA_DB_USERNAME={{ .db_username }}
UPTIME_KUMA_DB_PASSWORD={{ .db_password }}
{{- end -}}
EOT
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
