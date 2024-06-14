job "plantuml" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }
  
  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "plantuml" {
    network {
      port "http" {
        to = 8080
      }

      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
      }         
    }

    service {
      name = "plantuml"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
		"traefik.consulcatalog.connect=false",
        "traefik.http.routers.plantuml.rule=Host(`plantuml.shamsway.net`)",
        "traefik.http.routers.plantuml.entrypoints=web,websecure",
        "traefik.http.routers.plantuml.tls.certresolver=cloudflare",
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
              "tag" = "plantuml"
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