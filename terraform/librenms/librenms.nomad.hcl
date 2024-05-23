job "librenms" {
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

  group "librenms" {
    network {
      port "http" {
        to = 8000
      }
      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }      
    }

    volume "librenms-config" {
      type      = "host"
      read_only = false
      source    = "librenms-config"
    }

    service {
      name = "librenms"
      provider = "consul"
      task = "librenms"
      port = "http"

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

    service {
      name = "mysql"
      provider = "consul"
      task = "mysql"
      port = "3306"

      connect {
        native = true
      }
              
      check {
        name     = "tcp"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "librenms" {
      driver = "podman"
      #user = "1000"

      config {
        image = "docker.io/librenms/librenms:24.4.1"
        ports = ["http"]
        userns = "keep-id:uid=1000,gid=1000"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "librenms"
            }
          ]
        }         
      }

      env {
        TZ = "America/New_York"
        PUID = "1000"
        PGID = "1000"
        DB_HOST = "localhost"
        DB_NAME = "librenms"
        DB_USER = "librenms"
        DB_PASSWORD = "As3cur3P@ssw0rd!"
        DB_TIMEOUT = "60"
        REDIS_HOST = "redis.service.consul"
        REDIS_DB = "2"
        REDIS_CACHE_DB = "3"
      }

      volume_mount {
        volume      = "librenms-config"
        destination = "/data"
        read_only   = false
      }

      resources {
        memory = 256
      }
    }

    task "mysql" {
      driver = "podman"
      user = "mysql"

      config {
        image = "docker.io/mariadb:10"
        userns = "keep-id:uid=999,gid=999"
        command = "mysqld"
        args = ["--innodb-file-per-table=1", "--lower-case-table-names=0", "--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "librenms"
            }
          ]
        }         
      }

      env {
        TZ = "America/New_York"
        MYSQL_ALLOW_EMPTY_PASSWORD = "yes"
        MYSQL_DATABASE = "librenms"
        MYSQL_USER = "librenms"
        MYSQL_PASSWORD = "As3cur3P@ssw0rd!"    
      }

      volume_mount {
        volume      = "librenms-config"
        destination = "/var/lib/mysql"
        read_only   = false
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }

  }
}