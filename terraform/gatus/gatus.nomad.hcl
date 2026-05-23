job "gatus" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "gatus" {
    count = 1

    network {
      port "http" {
        static = 8080
        to     = 8080
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"
      task     = "gatus"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
        "homepage.group=Monitoring",
        "homepage.name=Gatus",
        "homepage.icon=gatus",
        "homepage.description=Health Checks",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "gatus" {
      driver = "podman"

      config {
        image  = "${image}"
        ports  = ["http"]
        volumes = [
          "local/config.yaml:/config/config.yaml",
          "/mnt/services/gatus/data:/data",
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

      template {
        destination = "$${NOMAD_TASK_DIR}/config.yaml"
        data        = <<EOT
${config_yaml}
EOT
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
