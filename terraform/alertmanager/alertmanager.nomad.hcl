job "alertmanager" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "alertmanager" {
    count = 1

    network {
      port "http" {
        static = 9093
        to     = 9093
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"
      task     = "alertmanager"

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
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/-/healthy"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "alertmanager" {
      driver = "podman"

      config {
        image  = "${image}"
        ports  = ["http"]
        args = [
          "--config.file=/etc/alertmanager/alertmanager.yml",
          "--storage.path=/data",
          "--web.listen-address=0.0.0.0:9093",
        ]
        volumes = [
          "local/alertmanager.yml:/etc/alertmanager/alertmanager.yml",
          "/mnt/services/alertmanager/data:/data",
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
        destination   = "$${NOMAD_TASK_DIR}/alertmanager.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        data          = <<EOT
${config_yaml}
EOT
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
