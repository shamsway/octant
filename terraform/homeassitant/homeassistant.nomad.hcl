job "homeassistant" {
  datacenters = ["shamsway"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "${meta.rootless}"
    value = "false"
  }

  # Temporary until lab is fully on physical hardware
  affinity {
    attribute = "${meta.class}"
    value     = "physical"
    weight    = 100
  }

  constraint {
    attribute = "${node.unique.name}"
    value = "jerry-agent-root"
  }

  group "homeassistant" {
    network {
      port "http" {
        static = 8123
        to = 8123
      }
      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }      
    }

    volume "homeassistant-data" {
      type      = "host"
      read_only = false
      source    = "homeassistant-data"
    }

    service {
      name = "homeassistant"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.homeassistant.rule=Host(`ha.shamsway.net`)",
        "traefik.http.routers.homeassistant.entrypoints=web,websecure",
        "traefik.http.routers.homeassistant.tls.certresolver=cloudflare",
        "traefik.http.routers.homeassistant.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }
              
      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "homeassistant" {
      driver = "podman"

      config {
        image = "ghcr.io/home-assistant/home-assistant:stable"
        privileged = true
        network_mode = "host"
        ports = ["http"]
        volumes = ["/etc/localtime:/etc/localtime:ro", "/run/dbus:/run/dbus:ro"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "homeassistant"
            }
          ]
        }         
      }

      volume_mount {
        volume      = "homeassistant-data"
        destination = "/config"
        read_only   = false
      }

      env {
        
      }

      resources {
        memory = 512
      }
    }
  }
}