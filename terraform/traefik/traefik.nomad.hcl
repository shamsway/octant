job "traefik" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "traefik" {
    count = 1
    network {
      port "http" {
        static = "80"
      }
      port "https" {
        static = "443"
      }
      port "metrics" {
        to = "8082"
      }
      port "admin" {
        static = "9002"
      }
      dns {
        servers = ${dns}
      }
    }

    update {
      max_parallel     = 1
      min_healthy_time = "30s"
      auto_revert      = true
    }

    service {
      name = "traefik-http"
      port = "http"
      tags = [
        "traefik",
        "traefik.enable=true",
        "traefik.http.routers.dashboard.rule=Host(`traefik-http.${domain}`)",
        "traefik.http.routers.dashboard.service=api@internal",
        "traefik.http.routers.dashboard.entrypoints=web,websecure",
      ]
      check {
        name     = "alive"
        type     = "tcp"
        port     = "http"
        interval = "10s"
        timeout  = "5s"
      }
    }

    service {
      name = "traefik"
      port = "https"
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "5s"
      }
    }

    service {
      name = "traefik-admin"
      provider = "consul"
      port = "admin"
      check {
        name     = "alive"
        type     = "http"
        port     = "admin"
        path     = "/ping"
        interval = "10s"
        timeout  = "5s"
      }
      tags = [
        "traefik","traefik.enable=true","lb", "admin",
        "traefik.http.routers.traefik-dash.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.traefik-dash.service=api@internal",
        "traefik.http.routers.traefik-dash.entrypoints=traefik",
        "homepage.group=Infrastructure",
        "homepage.name=Traefik",
        "homepage.icon=traefik",
        "homepage.description=Reverse Proxy",
        "homepage.href=http://traefik.${domain}:9002",
        "homepage.weight=10",
      ]
    }

    service {
      name = "traefik-metrics"
      tags = ["lb", "exporter", "metrics", "prometheus.scrape"]
      provider = "consul"
      port = "metrics"
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "5s"
        path     = "/ping"
      }

    }

    task "traefik" {
      driver = "podman"

      config {
        image = "${image}"
        args  = ["--configFile", "$${NOMAD_TASK_DIR}/traefik.toml"]
        ports = ["http", "https", "metrics", "admin"]
        volumes = [
          "/mnt/services/traefik/certs:/acme",
          "/mnt/services/traefik/data:/traefik-data",
          "/opt/octant/config/tls:/tls:ro",
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

      resources {
        memory = 128
      }

      logs {
        max_files     = 10
        max_file_size = 20
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/traefik" -}}
CLOUDFLARE_EMAIL={{ .cloudflare_username }}
CLOUDFLARE_API_KEY={{ .cloudflare_api_key }}
{{- end -}}
EOT
      }

      template {
          data = <<EOH
{{ with nomadVar "nomad/jobs/traefik" }}{{ .traefik_toml }}{{ end }}
EOH
        destination = "local/traefik.toml"
      }

    }
  }
}
