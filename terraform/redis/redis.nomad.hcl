job "redis" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "redis" {
    network {
      port "redis" {
        static = 6379
        to = 6379
      }
      dns {
        servers = ${dns}
      }      
    }

    service {
      name = "${servicename}"
      provider = "consul"
      port = "redis"

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

    task "redis" {
      driver = "podman"
      user = "redis"

      config {
        image = "${image}"
        ports = ["redis"]
        userns = "keep-id:uid=999,gid=999"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
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