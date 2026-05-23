job "rocketchat" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "rocketchat" {
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

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
        "homepage.group=Apps",
        "homepage.name=Rocket.Chat",
        "homepage.icon=rocket-chat",
        "homepage.description=Team Chat",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        interval = "60s"
        timeout  = "5s"
      }
    }

    task "rocketchat" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"

        volumes = [
          "/mnt/services/rocketchat/uploads:/app/uploads"
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
        PORT                                        = "3000"
        ROOT_URL                                    = "https://${servicename}.${domain}"
        TZ                                          = "America/New_York"
        OVERWRITE_SETTING_SMTP_Host                 = ""
        OVERWRITE_SETTING_Accounts_EmailVerification = "false"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/rocketchat" }}
MONGO_URL=mongodb://{{ .mongo_username }}:{{ .mongo_password }}@${mongo_hosts}/${mongo_db}?replicaSet=rs0&authSource=admin
MONGO_OPLOG_URL=mongodb://{{ .mongo_username }}:{{ .mongo_password }}@${mongo_hosts}/local?replicaSet=rs0&authSource=admin
{{- end }}
EOT
      }

      resources {
        cpu    = 500
        memory = 2048
      }
    }
  }
}
