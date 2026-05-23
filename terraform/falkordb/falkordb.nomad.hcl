job "falkordb" {
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

  group "falkordb" {
    count = 1

    network {
      port "redis" {
        to = 6379
      }

      port "ui" {
        to = 3000
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "redis"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=false",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }

    service {
      name     = "${servicename}-ui"
      provider = "consul"
      port     = "ui"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}-ui.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}-ui.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}-ui.tls.certresolver=${certresolver}",
        "homepage.group=Databases",
        "homepage.name=FalkorDB",
        "homepage.icon=si-redis",
        "homepage.description=Graph DB (Redis)",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "falkordb" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["redis", "ui"]

        volumes = [
          "/mnt/services/falkordb/data:/data"
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
        FALKORDB_ARGS = "THREAD_COUNT 4"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/falkordb" -}}
REDIS_ARGS=--requirepass {{ .FALKORDB_PASSWORD }} --appendonly yes
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
