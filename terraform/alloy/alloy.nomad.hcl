job "alloy" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "system"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "alloy" {
    constraint {
      attribute = "$${attr.consul.version}"
      operator  = "semver"
      value     = ">= 1.8.0"
    }

    ephemeral_disk {
      size = 300
    }

    network {
      port "http" {
        static = 12345
        to     = 12345
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"

      check {
        name     = "ready"
        type     = "http"
        path     = "/-/ready"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "alloy" {
      driver = "podman"

      config {
        image  = "${image}"
        args = [
          "run",
          "--server.http.listen-addr=0.0.0.0:12345",
          "--storage.path=/var/lib/alloy/data",
          "/etc/alloy/config.alloy",
        ]
        ports = ["http"]
        volumes = [
          "/var/log/journal:/var/log/journal:ro",
          "local/config.alloy:/etc/alloy/config.alloy",
        ]
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
        destination = "local/config.alloy"
        data        = <<EOT
${config_alloy}
EOT
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
