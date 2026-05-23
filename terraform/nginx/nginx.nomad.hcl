job "nginx" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
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
        servers = ${dns}
      }
    }

    volume "nginx-data" {
      type      = "host"
      read_only = true
      source    = "nginx-data"
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
        "homepage.group=Infrastructure",
        "homepage.name=Nginx",
        "homepage.icon=nginx",
        "homepage.description=Static Web Server",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "nginx" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["http", "httpalt", "https"]
        userns             = "keep-id:uid=101,gid=101"
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
