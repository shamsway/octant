job "grafana" {
  region      = "home"
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "(linux|darwin)"
    operator  = "regexp"
  }

  group "grafana" {
    count = 1 

    network {
      port "http" {
        static = 3000
      }
    }

    service {
        name = "grafana"
        port = "http"
        provider = "consul"       

        tags = [
            "traefik.enable=true",
            "traefik.http.routers.grafana.rule=Host(`grafana.shamsway.net`)",
            "traefik.http.routers.grafana.entrypoints=web,websecure",
            "traefik.http.routers.grafana.tls.certresolver=cloudflare",
            "traefik.http.routers.grafana.middlewares=redirect-web-to-websecure@internal",       
        ]

        check {
            name     = "alive"
            type     = "http"
            path     = "/"
            interval = "10s"
            timeout  = "2s"
        }
    }

    volume "grafana-data" {
      type      = "host"
      read_only = false
      source    = "grafana-data"
    }

    volume "grafana-config" {
      type      = "host"
      read_only = false
      source    = "grafana-config"
    }    

    task "grafana" {
      driver = "podman"
      # user = "2000:100"

      config {
        image = "docker.io/grafana/grafana:10.4.1"
        ports = ["http"]        
        userns = "keep-id:uid=472,gid=472"
      }

      volume_mount {
        volume      = "grafana-data"
        destination = "/var/lib/grafana"
        read_only   = false
      }

      volume_mount {
        volume      = "grafana-config"
        destination = "/etc/grafana/"
        read_only   = false
      }      

      env {
        GF_PATHS_DATA = "/var/lib/grafana"
        GF_AUTH_BASIC_ENABLED = "false"
        #GF_INSTALL_PLUGINS = "grafana-piechart-panel"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}