job "ollama" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "false"
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
        image = "${image}"
        ports = ["api"]
        privileged = true
        volumes = ["/mnt/llm-models:/root/.ollama"]
        // logging = {
        //   driver = "journald"
        //   options = [
        //     {
        //       "tag" = "ollama"
        //     }
        //   ]
        // }          
      }

      resources {
        memory = 256
        device "nvidia/gpu" {
          count = 1    
        }        
      }      
    }
  }
}