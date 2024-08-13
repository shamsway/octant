variable "datacenter" {
  type = string
  default = "octant"
}

variable "domain" {
  type = string
  default = "octant.net"
}

variable "certresolver" {
  type = string
  default = "cloudflare"
}

variable "servicename" {
  type = string
  default = "homeassistant"
}

variable "ha_image" {
  type = string
  default = "ghcr.io/home-assistant/home-assistant:2024.6"
}

variable "ma_image" {
  type = string
  default = "ghcr.io/music-assistant/server:2.0.4"
}

variable "whisper_image" {
  type = string
  default = "docker.io/rhasspy/wyoming-whisper:2.1.0"
}

variable "piper_image" {
  type = string
  default = "docker.io/rhasspy/wyoming-piper:1.5.0"
}

variable "cloudflared_image" {
  type = string
  default = "docker.io/cloudflare/cloudflared:latest"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

job "homeassistant" {
  datacenters = ["${var.datacenter}"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "${meta.rootless}"
    value = "false"
  }

  # Pin Home Assistant to a node so it's IP doesn't change
  constraint {
    attribute = "${node.unique.name}"
    value = "server1-agent-root"
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
        servers = var.dns
      }      
    }

    volume "homeassistant-data" {
      type      = "host"
      read_only = false
      source    = "homeassistant-data"
    }

    service {
      name = var.servicename
      task = "homeassistant"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${var.servicename}.rule=Host(`ha.${var.domain}`)",
        "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",  
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
        "traefik.http.routers.musicassistant.rule=Host(`music.${var.domain}`)",
        "traefik.http.routers.musicassistant.entrypoints=web,websecure",
        "traefik.http.routers.musicassistant.tls.certresolver=${var.certresolver}",
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
        image = var.ha_image
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
        image = var.ma_image
        privileged = true
        network_mode = "host"
        ports = ["music","streams"]
        volumes = ["/mnt/services/musicassistant:/data"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "musicassistant"
            }
          ]
        }         
      }

      resources {
        memory = 512
      }
    }

    task "whisper" {
      driver = "podman"

      config {
        image = var.whisper_image
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
        image = var.piper_image
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
        servers = var.dns
      }      
    }

    task "ha_cloudflared" {
      driver = "podman"
      user = "nonroot"

      config {
        image = var.cloudflared_image
        network_mode = "bridge"
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