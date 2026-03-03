job "gitea" {
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

  group "gitea" {
    count = 1

    network {
      port "http" {
        to = 3000
      }

      port "ssh" {
        static = 2222
        to     = 2222
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
        path     = "/api/healthz"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "gitea" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["http", "ssh"]
        image_pull_timeout = "15m"

        volumes = [
          "/mnt/services/gitea/data:/data"
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

        # Gitea configuration via environment variables
        # Uses GITEA__section__key pattern mapping to app.ini
        GITEA__server__DOMAIN             = "${servicename}.${domain}"
        GITEA__server__ROOT_URL           = "https://${servicename}.${domain}/"
        GITEA__server__HTTP_PORT          = "3000"
        GITEA__server__SSH_PORT           = "2222"
        GITEA__server__SSH_LISTEN_PORT    = "2222"
        GITEA__database__DB_TYPE          = "sqlite3"
        GITEA__database__PATH             = "/data/gitea/gitea.db"
        GITEA__service__DISABLE_REGISTRATION = "false"
        GITEA__log__LEVEL                 = "Info"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
