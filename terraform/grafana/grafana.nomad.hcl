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
  default = "grafana"
}

variable "image" {
  type = string
  default = "docker.io/grafana/grafana:10.4.1"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

job "grafana" {
  region      = "home"
  datacenters = ["${var.datacenter}"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }
  
  group "grafana" {
    count = 1 

    network {
      port "http" {
        static = 3000
      }

      dns {
        servers = var.dns
      }        
    }

    service {
        name = var.servicename
        port = "http"
        provider = "consul"

        connect {
          native = true
        }        

        tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",
          "traefik.http.routers.${var.servicename}.rule=Host(`${var.servicename}.${var.domain}`)",
          "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
          "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
          "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",    
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

      config {
        image = var.image
        ports = ["http"]        
        userns = "keep-id:uid=472,gid=472"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "grafana"
            }
          ]
        }        
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
        GF_ALLOW_LOADING_UNSIGNED_PLUGINS = "natel-discrete-panel"
        GF_INSTALL_PLUGINS = "natel-discrete-panel, grafana-piechart-panel, grafana-clock-panel, grafana-simple-json-datasource"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}