job "traefik" {
  region = "home"
  datacenters = ["shamsway"]
  type = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  meta {
    version = "2"
  }

  affinity {
    attribute = "${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "lbs" {
    count = 1
    network {
      port "http" {
        static = "80"
      }
      port "https" {
        static = "443"
      }
      port "api" {
        static = "8081"
      }
      port "metrics" {
        static = "8082"
      }
      port "admin" {
        static = "9002"
      }
      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
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
        "traefik.http.routers.dashboard.rule=Host(`traefik-http.shamsway.net`)",
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
        "traefik.http.routers.dashboard.rule=Host(`traefik.shamsway.net`)"
        #"metrics",
        #"metrics_port=8082",
        #"metrics_scheme=http",
        #"metrics_path=/metrics",
        #"traefik.tags=clusterservice",
        #"traefik.consulcatalog.connect=false",
        #"traefik.http.routers.metrics.rule=PathPrefix(`/metrics`)",
        #"traefik.http.routers.metrics.entrypoints=api",
        #"traefik.http.routers.metrics.service=prometheus@internal",
        #"traefik.http.routers.api.rule=(PathPrefix(`/api`) || PathPrefix(`/dashboard`))",
        #"traefik.http.routers.api.entrypoints=api",
        #"traefik.http.routers.api.service=api@internal",
        #"traefik.http.routers.api.middlewares=AdminAuth@file"
      ]
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
        image = "docker.io/traefik:v3.0"
        args  = ["--configFile", "/traefik-config/traefik.toml"]
        ports = ["http", "https", "api", "metrics", "admin"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "traefik"
            }
          ]
        }
      }

      env {
        CLOUDFLARE_EMAIL = "mattadamelliott@gmail.com"
        CLOUDFLARE_API_KEY = "b0f9feb2cfce1ba2618dc83e17285682fd44e"
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
      resources {
        memory = 128
      }

      logs {
        max_files     = 10
        max_file_size = 20
      }
    }
  }
}