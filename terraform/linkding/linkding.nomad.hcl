job "linkding" {
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

  group "linkding" {
    count = 1

    network {
      port "http" {
        to = 9090
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
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "linkding" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"

        volumes = [
          "/mnt/services/linkding/data:/etc/linkding/data"
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
{{- with nomadVar "nomad/jobs/linkding" -}}
LD_SUPERUSER_NAME={{ .LD_SUPERUSER_NAME }}
LD_SUPERUSER_PASSWORD={{ .LD_SUPERUSER_PASSWORD }}
{{- end -}}
EOT
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
