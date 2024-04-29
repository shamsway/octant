job "influxdb" {
  region      = "home"
  datacenters = ["shamsway"]
  type        = "service"
  
  constraint {
    attribute = "${attr.kernel.name}"
    value     = "(linux|darwin)"
    operator  = "regexp"
  }

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
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

      config {
        image = "docker.io/influxdb:2.7"
        ports = ["http"]
        userns = "keep-id:uid=1000,gid=1000"
      }
      env {
        DOCKER_INFLUXDB_INIT_ADMIN_TOKEN = "pharisee-window-flemish"
        DOCKER_INFLUXDB_INIT_BUCKET = "hell-in-a-bucket"
        DOCKER_INFLUXDB_INIT_MODE = "setup"
        DOCKER_INFLUXDB_INIT_ORG = "shamsway"
        DOCKER_INFLUXDB_INIT_PASSWORD = "austral-damage-paw"
        DOCKER_INFLUXDB_INIT_RETENTION = "365d"
        DOCKER_INFLUXDB_INIT_USERNAME = "admin"
      }
      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}