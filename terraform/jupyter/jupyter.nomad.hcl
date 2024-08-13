job "jupyter" {
  region = "${var.region}"
  datacenters = ["${var.datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "jupyter" {
    network {
      port "http" {
        static = 8888
        to = 8888
      }

      dns {
        servers = var.dns
      }         
    }

    service {
      name = var.servicename
      provider = "consul"
      port = "http"
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
        interval = "60s"
        timeout  = "5s"
      }
    }       
    
    task "jupyter" {
      driver = "podman"

      config {
        image = "${var.image}"
        ports = ["http"]
        image_pull_timeout = "15m"
        args = ["start-notebook.py","--IdentityProvider.token='6476bd640f20936608a5f0b6b5f00820'","--NotebookApp.allow_origin='https://colab.research.google.com'","--NotebookApp.port_retries=0", "--NotebookApp.disable_check_xsrf=True"]
        userns = "keep-id:uid=1000,gid=100"
        volumes = ["/mnt/services/jupyter/data:/home/jovyan/work"]        
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${var.servicename}"
            }
          ]
        }                 
      }

      env {
        JUPYTER_ENABLE_LAB = "yes"
      }

      resources {
        cpu    = 500
        memory = 768
      }
    }
  }
}