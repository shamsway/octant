job "minio" {
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

  group "minio" {
    count = 1

    network {
      port "api" {
        to = 9000
      }

      port "console" {
        to = 9001
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "api"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=false",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/minio/health/live"
        interval = "30s"
        timeout  = "5s"
      }
    }

    service {
      name     = "${servicename}-console"
      provider = "consul"
      port     = "console"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}-console.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}-console.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}-console.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}-console.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        name     = "console"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "minio" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["api", "console"]

        args = [
          "server", "/data",
          "--console-address", ":9001",
        ]

        volumes = [
          "/mnt/services/minio/data:/data"
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
{{- with nomadVar "nomad/jobs/minio" }}
MINIO_ROOT_USER={{ .MINIO_ROOT_USER }}
MINIO_ROOT_PASSWORD={{ .MINIO_ROOT_PASSWORD }}
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
