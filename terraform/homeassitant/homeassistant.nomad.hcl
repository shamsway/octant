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

      port "music" {
        static = 8095
        to = 8095
      }

      port "streams" {
        static = 8097
        to = 8097
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
      task = "homeassistant"
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

    service {
      name = "music"
      task = "musicassistant"
      provider = "consul"
      port = "music"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.musicassistant.rule=Host(`music.shamsway.net`)",
        "traefik.http.routers.musicassistant.entrypoints=web,websecure",
        "traefik.http.routers.musicassistant.tls.certresolver=cloudflare",
        "traefik.http.routers.musicassistant.middlewares=redirect-web-to-websecure@internal",
      ]
      connect {
        native = true
      }
              
      check {
        name     = "alive"
        type     = "tcp"
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
        memory = 864
      }
    }

    task "musicassistant" {
      driver = "podman"

      config {
        image = "ghcr.io/music-assistant/server"
        privileged = true
        network_mode = "host"
        ports = ["music","streams"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "musicassistant"
            }
          ]
        }         
      }

      volume_mount {
        volume      = "homeassistant-data"
        destination = "/data"
        read_only   = false
      }

      env {
        
      }

      resources {
        memory = 512
      }
    }

    task "whisper" {
      driver = "podman"

      config {
        image = "docker.io/rhasspy/wyoming-whisper"
        args = ["--model", "tiny-int8", "--language", "en"]
        network_mode = "host"
      }

      resources {
        memory = 128
      }
    }

    task "piper" {
      driver = "podman"

      config {
        image = "docker.io/rhasspy/wyoming-piper"
        args = ["--voice", "en_US-lessac-medium"]
        network_mode = "host"
      }

      resources {
        memory = 128
      }
    }    
  }

  group "ha_cloudflared" {
    network {      
      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }      
    }

    task "ha_cloudflared" {
      driver = "podman"
      user = "nonroot"

      config {
        image = "docker.io/cloudflare/cloudflared:latest"
        network_mode = "bridge"
        #entrypoint = ["cloudflared"]
        #args = ["tunnel", "run", "--token", "eyJhIjoiMmYxYzBlZWU4NmU0YTg1OTkyMWQ2MmY4ZTU3NzYwYmYiLCJ0IjoiNWUxNGE5ZjMtMjkzNy00NWQwLWIzNDAtYmEzZTU1NTI0N2YwIiwicyI6Ik9HRTFZekF4WkRFdE5XUmhPUzAwWkRjekxUaGlZbVl0T1dJeU1Ua3pOams0WVdWbCJ9"]
        args = ["tunnel", "--loglevel", "debug", "run"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "ha_cloudflared"
            }
          ]
        }         
      }

      env {
        TUNNEL_TOKEN="eyJhIjoiMmYxYzBlZWU4NmU0YTg1OTkyMWQ2MmY4ZTU3NzYwYmYiLCJ0IjoiNWUxNGE5ZjMtMjkzNy00NWQwLWIzNDAtYmEzZTU1NTI0N2YwIiwicyI6Ik9HRTFZekF4WkRFdE5XUmhPUzAwWkRjekxUaGlZbVl0T1dJeU1Ua3pOams0WVdWbCJ9"
      }

      resources {
        memory = 128
      }      
    }
  }
}