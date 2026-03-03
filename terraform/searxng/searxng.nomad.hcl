job "searxng" {
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

  group "searxng" {
    count = 1

    network {
      port "http" {
        to = 8080
      }

      dns {
        servers = ["${join("\", \"", dns)}"]
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"
      task     = "searxng"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "searxng" {
      driver = "podman"

      config {
        image              = "${searxng_image}"
        ports              = ["http"]
        volumes            = ["/mnt/services/searxng/config:/etc/searxng"]
        image_pull_timeout = "15m"
        cap_add            = ["CHOWN", "SETGID", "SETUID"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
      }

      env {
        SEARXNG_BASE_URL = "https://${servicename}.${domain}/"
        UWSGI_WORKERS    = "${uwsgi_workers}"
        UWSGI_THREADS    = "${uwsgi_threads}"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    task "redis" {
      driver = "podman"

      config {
        image              = "${redis_image}"
        image_pull_timeout = "15m"
        volumes            = ["/mnt/services/searxng/data:/data"]
        cap_add            = ["SETGID", "SETUID", "DAC_OVERRIDE"]
        command            = "valkey-server"
        args               = ["--save", "30", "1", "--loglevel", "warning"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "searxng-redis"
            }
          ]
        }
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
