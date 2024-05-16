job "redis" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  # Temporary until lab is fully on physical hardware
  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "redis" {
    network {
      port "redis" {
        static = 6379
        to = 6379
      }
      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }      
    }

    // volume "redis-data" {
    //   type      = "host"
    //   read_only = false
    //   source    = "redis-data"
    // }

    service {
      name = "redis"
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
              "tag" = "redis"
            }
          ]
        }         
      }

      // volume_mount {
      //   volume      = "redis-data"
      //   destination = "/data"
      //   read_only   = false
      // }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}