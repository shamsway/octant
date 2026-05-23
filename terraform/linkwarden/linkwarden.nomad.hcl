job "linkwarden" {
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

  group "linkwarden" {
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
        "homepage.name=Linkwarden",
        "homepage.icon=linkwarden",
        "homepage.description=Bookmark Archive",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "linkwarden" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"

        volumes = [
          "/mnt/services/linkwarden/data:/data/data"
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
        TZ            = "America/New_York"
        NEXTAUTH_URL  = "https://${servicename}.${domain}"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/linkwarden" -}}
DATABASE_URL={{ .DATABASE_URL }}
NEXTAUTH_SECRET={{ .NEXTAUTH_SECRET }}
{{- end -}}
EOT
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
