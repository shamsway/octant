job "mariadb" {
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

  group "mariadb" {
    network {
      port "mariadb" {
        static = 3306
        to = 3306
      }
      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }      
    }

    volume "librenms-data" {
      type      = "host"
      read_only = false
      source    = "librenms-data"
    }

    service {
      name = "mariadb"
      provider = "consul"
      port = "mariadb"

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

    task "mariadb" {
      driver = "podman"
      user = "mysql"

      config {
        image = "docker.io/mariadb:10"
        userns = "keep-id:uid=999,gid=999"
        command = "mysqld"
        ports = ["mariadb"]
        args = ["--innodb-file-per-table=1", "--lower-case-table-names=0", "--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "mariadb"
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
        volume      = "librenms-data"
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