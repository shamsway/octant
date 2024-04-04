job "influxdb" {
  region      = "home"
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "(linux|darwin)"
    operator  = "regexp"
  }

  group "influxdb" {
    count = 1

    network {
      port "http" {
        static = 8086
      }
    }

    service {
      name = "influxdb"
      provider = "consul"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.influxdb.rule=Host(`influxdb.shamsway.net`)",
        "traefik.http.routers.influxdb.entrypoints=web,websecure",
        "traefik.http.routers.influxdb.tls.certresolver=cloudflare",
        "traefik.http.routers.influxdb.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    volume "influxdb-config" {
      type      = "host"
      read_only = false
      source    = "influxdb-config"
    }

    volume "influxdb-data" {
      type      = "host"
      read_only = false
      source    = "influxdb-data"
    }

    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    task "influxdb" {
      driver = "podman"

      config {
        image = "docker.io/influxdb:2.7"
        ports = ["http"]
        userns = "keep-id:uid=1000,gid=1000"
      }

      volume_mount {
        volume      = "influxdb-data"
        destination = "/var/lib/influxdb2"
        read_only   = false
      }
      volume_mount {
        volume      = "influxdb-config"
        destination = "/etc/influxdb2"
        read_only   = false
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}