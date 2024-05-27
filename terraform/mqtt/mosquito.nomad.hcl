job "mqtt" {
  region = "home"
  datacenters = ["shamsway"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  # Temporary until lab is fully on physical hardware
  affinity {
    attribute = "${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "mqtt" {
    network {
      port "mqtt" {
        static = 1883
        to = 1883
      }
      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }      
    }

    service {
      name = "mqtt"
      provider = "consul"
      port = "mqtt"

      connect {
        native = true
      }
            
      check {
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "mqtt" {
      driver = "podman"
      user = "1883"

      config {
        image = "docker.io/eclipse-mosquitto:2.0.18"
        userns = "keep-id:uid=1883,gid=1883"
        volumes = ["/mnt/services/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf","/mnt/services/mosquitto/data:/mosquitto/data","/mnt/services/mosquitto/log:/mosquitto/log"]
        ports = ["mqtt"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "mqtt"
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