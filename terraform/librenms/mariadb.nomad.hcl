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
  default = "mariadb"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "image" {
  type = string
  default = "docker.io/mariadb:10"
}

variable "TZ" {
  type    = string
  default = "America/New_York"
}

variable "MYSQL_ALLOW_EMPTY_PASSWORD" {
  type    = string
  default = "yes"
}

variable "MYSQL_DATABASE" {
  type    = string
  default = "librenms"
}

variable "MYSQL_USER" {
  type    = string
  default = "librenms"
}

variable "MYSQL_PASSWORD" {
  type    = string
  default = "As3cur3P@ssw0rd!"
}

job "mariadb" {
  region = "home"
  datacenters = ["${var.datacenter}"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  group "mariadb" {
    network {
      port "mariadb" {
        static = 3306
        to = 3306
      }
      dns {
        servers = var.dns
      }      
    }

    volume "librenms-data" {
      type      = "host"
      read_only = false
      source    = "librenms-data"
    }

    service {
      name = "${var.servicename}"
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
        image = "${var.image}"
        userns = "keep-id:uid=999,gid=999"
        command = "mysqld"
        ports = ["mariadb"]
        args = ["--innodb-file-per-table=1", "--lower-case-table-names=0", "--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${var.servicename}"
            }
          ]
        }         
      }

      env {
        TZ = var.TZ
        MYSQL_ALLOW_EMPTY_PASSWORD = var.MYSQL_ALLOW_EMPTY_PASSWORD
        MYSQL_DATABASE = var.MYSQL_DATABASE
        MYSQL_USER = var.MYSQL_USER
        MYSQL_PASSWORD = var.MYSQL_PASSWORD 
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