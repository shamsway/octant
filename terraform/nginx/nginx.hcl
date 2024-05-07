job "nginx" {
  region      = "home"
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  group "nginx" {
    count = 1 

    network {
      port "http" {
        to = 8080
      }

      port "httpalt" {
        to = 8081
      }      

      port "https" {
        to = 9443
      }      
    }

    service {
      name = "web"
      port = "http"
      provider = "consul"       

      tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",          
          "traefik.http.routers.web.rule=Host(`web.shamsway.net`)",
          "traefik.http.routers.web.entrypoints=web,websecure",
          "traefik.http.routers.web.tls.certresolver=cloudflare", 
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

    volume "nginx-data" {
      type      = "host"
      read_only = true
      source    = "nginx-data"
    }   

    task "nginx" {
      driver = "podman"

      config {
        image = "docker.io/nginxinc/nginx-unprivileged:1.25.4"
        ports = ["http", "httpalt", "https"]        
        userns = "keep-id:uid=101,gid=101"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "nginx"
            }
          ]
        }        
      }

      volume_mount {
        volume      = "nginx-data"
        destination = "/usr/share/nginx/html"
        read_only   = true
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}