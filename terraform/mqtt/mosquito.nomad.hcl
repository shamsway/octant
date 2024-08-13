variable "datacenter" {
  type = string
  default = "octant"
}

variable "domain" {
  type = string
  default = "octant.net"
}

variable "certresolver" {
  type = string
  default = "cloudflare"
}

variable "servicename" {
  type = string
  default = "mqtt"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "image" {
  type = string
  default = "docker.io/eclipse-mosquitto:2.0.18"
}

job "mqtt" {
  region = "home"
  datacenters = ["${var.datacenter}"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  group "mqtt" {
    network {
      port "mqtt" {
        static = 1883
        to = 1883
      }
      dns {
        servers = var.dns
      }      
    }

    service {
      name = var.servicename
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
        image = var.image
        userns = "keep-id:uid=1883,gid=1883"
        volumes = ["/mnt/services/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf","/mnt/services/mosquitto/data:/mosquitto/data","/mnt/services/mosquitto/log:/mosquitto/log"]
        ports = ["mqtt"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${var.servicename}"
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