job "ollama" {
  datacenters = ["shamsway"]
  type = "service"

  constraint {
    attribute = "${meta.gpu}"
    value = "true"
  }

  group "ollama" {
    network {
      port "api" {
        static = 11434
        to = 11434
      }
      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
      }      
    }

    volume "llm-models" {
      type      = "host"
      read_only = false
      source    = "llm-models"
    }

    service {
      name = "ollama"
      provider = "consul"
      port = "api"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.ollama.rule=Host(`ollama.shamsway.net`)",
        "traefik.http.routers.ollama.entrypoints=web,websecure",
        "traefik.http.routers.ollama.tls.certresolver=cloudflare",
        "traefik.http.routers.ollama.middlewares=redirect-web-to-websecure@internal",
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

    task "ollama" {
      driver = "docker"
 
      config {
        image = "docker.io/ollama/ollama"
        force_pull = true
        ports = ["api"]
        privileged = true
      }
 
      logs {
        disabled = true
      }

      volume_mount {
        volume      = "llm-models"
        destination = "/root/.ollama"
        read_only   = false
      }

      resources {
        memory = 128
        device "nvidia/gpu" { }        
      }      
    }
  }
}