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
  default = "nginx"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "image" {
  type = string
  default = "docker.io/nginxinc/nginx-unprivileged:1.25.4"
}
  
  job "nginx" {
    region      = "home"
    datacenters = ["${var.datacenter}"]
    type        = "service"
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

        dns {
          servers = var.dns
        }        
      }

      service {
        name = var.servicename
        port = "http"
        provider = "consul"       

        tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",          
          "traefik.http.routers.${var.servicename}.rule=Host(`${var.servicename}.${var.domain}`)",
          "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
          "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
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
          image = var.image
          ports = ["http", "httpalt", "https"]        
          userns = "keep-id:uid=101,gid=101"
          logging = {
            driver = "journald"
            options = [
              {
                "tag" = "${var.servicename}"
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