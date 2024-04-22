job "nginx" {
  region      = "home"
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "(linux|darwin)"
    operator  = "regexp"
  }

  group "nginx" {
    count = 1 

    network {
      port "http" {
        static = 8080
      }

      port "https" {
        static = 9443
      }      
    }

    service {
        name = "nginx"
        port = "http"
        provider = "consul"       

        tags = [
            "traefik.enable=true",
            "traefik.http.routers.nginx.rule=Host(`nginx.shamsway.net`)",
            "traefik.http.routers.nginx.entrypoints=web,websecure",
            "traefik.http.routers.nginx.tls.certresolver=cloudflare",
            "traefik.http.routers.nginx.middlewares=redirect-web-to-websecure@internal",       
        ]

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
        ports = ["http", "https"]        
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