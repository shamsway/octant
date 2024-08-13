job "plantuml" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "plantuml" {
    network {
      port "http" {
        to = 8080
      }

      dns {
        servers = ${dns}
      }         
    }

    service {
      name = "${servicename}"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
		    "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
      ]

      connect {
        native = true
      }        

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "60s"
        timeout  = "5s"
      }
    }       
    
    task "plantuml" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["http"]
        image_pull_timeout = "15m"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }                 
      } 

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}