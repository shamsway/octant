job "mqtt" {
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

  group "mqtt" {
    count = 1

    network {
      port "mqtt" {
        static = 1883
        to     = 1883
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "mqtt"

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "mqtt" {
      driver = "podman"
      user   = "1883"

      config {
        image  = "${image}"
        ports  = ["mqtt"]
        userns = "keep-id:uid=1883,gid=1883"
        volumes = [
          "local/mosquitto.conf:/mosquitto/config/mosquitto.conf",
          "/mnt/services/mosquitto/data:/mosquitto/data",
          "/mnt/services/mosquitto/log:/mosquitto/log",
        ]
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

      template {
        data        = <<-EOT
${mosquitto_conf}
        EOT
        destination = "local/mosquitto.conf"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
