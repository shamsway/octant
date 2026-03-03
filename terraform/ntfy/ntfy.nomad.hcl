job "ntfy" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "ntfy" {
    network {
      port "http" {
        static = 8088
        to     = 80
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

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "ntfy" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"
        args               = ["serve"]
        volumes = [
          "/mnt/services/ntfy/config:/etc/ntfy",
          "/mnt/services/ntfy/data:/var/cache/ntfy",
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
        TZ                       = "${timezone}"
        NTFY_BASE_URL            = "http://${servicename}.${domain}"
        NTFY_CACHE_FILE          = "/var/cache/ntfy/cache.db"
        NTFY_AUTH_FILE           = "/var/cache/ntfy/auth.db"
        NTFY_AUTH_DEFAULT_ACCESS = "deny-all"
        NTFY_BEHIND_PROXY        = "true"
        NTFY_SMTP_SENDER_ADDR    = "${smtp_server}:${smtp_port}"
        NTFY_SMTP_SENDER_FROM    = "ntfy@${domain}"
        NTFY_SMTP_SENDER_USER    = "${smtp_username}"
        NTFY_SMTP_SENDER_PASS    = "${smtp_password}"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
