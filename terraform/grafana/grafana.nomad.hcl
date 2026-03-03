job "grafana" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "grafana" {
    count = 1

    network {
      port "http" {
        static = 3000
        to     = 3000
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      task     = "grafana"
      port     = "http"
      provider = "consul"

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
        path     = "/api/health"
        interval = "30s"
        timeout  = "10s"
      }
    }

    task "grafana" {
      driver = "podman"

      config {
        image  = "${image}"
        ports  = ["http"]
        userns = "keep-id:uid=472,gid=472"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
        volumes = [
          "/mnt/services/grafana/data:/var/lib/grafana",
          "local/datasources.yml:/etc/grafana/provisioning/datasources/lgtm.yml",
        ]
      }

      env {
        GF_PATHS_DATA         = "/var/lib/grafana"
        GF_AUTH_BASIC_ENABLED = "false"
        GF_PLUGINS_PREINSTALL = "grafana-clock-panel"
      }

      template {
        destination   = "local/datasources.yml"
        change_mode   = "noop"
        data          = <<EOT
${datasources_yaml}
EOT
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
