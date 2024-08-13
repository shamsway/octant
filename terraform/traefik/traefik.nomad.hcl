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
        to = "80"
      }
      port "https" {
        to = "443"
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

    volume "traefik-certs" {
      type      = "host"
      read_only = false
      source		= "traefik-certs"
    }  

    volume "traefik-config" {
      type      = "host"
      read_only = false
      source		= "traefik-config"
    }  

    volume "traefik-data" {
      type      = "host"
      read_only = false
      source		= "traefik-data"
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
        "traefik.http.routers.dashboard.rule=Host(`${servicename}.${domain}`)"
      ]
      connect {
        native = true
      }
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

      connect {
        native = true
      }
    }

    task "traefik" {
      driver = "podman"

      volume_mount {
        volume      = "traefik-certs"
        destination = "/acme"
        read_only   = false
      }

      volume_mount {
        volume      = "traefik-config"
        destination = "/traefik-config"
        read_only   = false
      }

      volume_mount {
        volume      = "traefik-data"
        destination = "/traefik-data"
        read_only   = false
      }

      config {
        image = "${image}"
        args  = ["--configFile", "$${NOMAD_TASK_DIR}/traefik.toml", "--providers.file.filename", "$${NOMAD_TASK_DIR}/dynamic.toml"]
        ports = ["http", "https", "metrics", "admin"]
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

      template {
          data = <<EOH
{{ with nomadVar "nomad/jobs/traefik" }}{{ .dynamic_toml }}{{ end }}
EOH
        destination = "local/dynamic.toml"
      }      
    }
  }
}