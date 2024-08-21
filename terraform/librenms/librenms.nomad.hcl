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
  default = "librenms"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "librenms_image" {
  type = string
  default = "docker.io/librenms/librenms:24.4.1"
}

variable "rrdcached_image" {
  type = string
  default = "docker.io/crazymax/rrdcached:1.8.0-r5"
}

variable "TZ" {
  type    = string
  default = "America/New_York"
}

variable "PUID" {
  type    = string
  default = "2000"
}

variable "PGID" {
  type    = string
  default = "2000"
}

variable "DB_HOST" {
  type    = string
  default = "mariadb.service.consul"
}

variable "DB_NAME" {
  type    = string
  default = "librenms"
}

variable "DB_USER" {
  type    = string
  default = "librenms"
}

variable "DB_PASSWORD" {
  type    = string
  default = "As3cur3P@ssw0rd!"
}

variable "DB_TIMEOUT" {
  type    = string
  default = "60"
}

variable "REDIS_HOST" {
  type    = string
  default = "redis.service.consul"
}

variable "REDIS_DB" {
  type    = string
  default = "2"
}

variable "REDIS_CACHE_DB" {
  type    = string
  default = "3"
}

variable "CACHE_DRIVER" {
  type    = string
  default = "redis"
}

variable "SESSION_DRIVER" {
  type    = string
  default = "redis"
}

variable "RRDCACHED_SERVER" {
  type    = string
  default = "rrdcached.service.consul:42217"
}

variable "MEMORY_LIMIT" {
  type    = string
  default = "256M"
}

variable "MAX_INPUT_VARS" {
  type    = string
  default = "1000"
}

variable "UPLOAD_MAX_SIZE" {
  type    = string
  default = "16M"
}

variable "OPCACHE_MEM_SIZE" {
  type    = string
  default = "128"
}

variable "REAL_IP_FROM" {
  type    = string
  default = "0.0.0.0/32"
}

variable "REAL_IP_HEADER" {
  type    = string
  default = "X-Forwarded-For"
}

variable "LOG_IP_VAR" {
  type    = string
  default = "http_x_forwarded_for"
}

variable "LIBRENMS_WEATHERMAP" {
  type    = string
  default = "true"
}

variable "LIBRENMS_SNMP_COMMUNITY" {
  type    = string
  default = "octant"
}

variable "LIBRENMS_BASE_URL" {
  type    = string
  default = "librenms.octant.net"
}

variable "DISPATCHER_NODE_ID" {
  type    = string
  default = "dispatcher"
}

variable "SIDECAR_DISPATCHER" {
  type    = string
  default = "1"
}

variable "LOG_LEVEL" {
  type    = string
  default = "LOG_INFO"
}

variable "WRITE_TIMEOUT" {
  type    = string
  default = "1800"
}

variable "WRITE_JITTER" {
  type    = string
  default = "1800"
}

variable "WRITE_THREADS" {
  type    = string
  default = "4"
}

variable "FLUSH_DEAD_DATA_INTERVAL" {
  type    = string
  default = "3600"
}

job "librenms" {
  region = "home"
  datacenters = ["${var.datacenter}"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "${meta.rootless}"
    value = "false"
  }

  group "librenms" {
    network {
      port "http" {
        to = 8000
      }
      port "rrdcached" {
        static = 42217
        to = 42217
      }

      dns {
        servers = var.dns
      }      
    }

    service {
      name = var.servicename
      provider = "consul"
      task = "librenms"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.${var.servicename}.rule=Host(`${var.servicename}.${var.domain}`)",
        "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }
            
      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    service {
      name = "rrdcached"
      provider = "consul"
      task = "librenms-rrdcached"
      port = "rrdcached"

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

    task "librenms" {
      driver = "podman"

      config {
        image = var.librenms_image
        ports = ["http"]
        cap_add = ["NET_RAW","NET_ADMIN"]
        volumes = ["/mnt/services/librenms/config:/data"]
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
        PUID = var.PUID
        PGID = var.PGID
        DB_HOST = var.DB_HOST
        DB_NAME = var.DB_NAME
        DB_USER = var.DB_USER
        DB_PASSWORD = var.DB_PASSWORD
        DB_TIMEOUT = var.DB_TIMEOUT
        REDIS_HOST = var.REDIS_HOST
        REDIS_DB = var.REDIS_DB
        REDIS_CACHE_DB = var.REDIS_CACHE_DB
        CACHE_DRIVER = var.CACHE_DRIVER
        SESSION_DRIVER = var.SESSION_DRIVER
        RRDCACHED_SERVER = var.RRDCACHED_SERVER
        MEMORY_LIMIT = var.MEMORY_LIMIT
        MAX_INPUT_VARS = var.MAX_INPUT_VARS
        UPLOAD_MAX_SIZE = var.UPLOAD_MAX_SIZE
        OPCACHE_MEM_SIZE = var.OPCACHE_MEM_SIZE
        REAL_IP_FROM = var.REAL_IP_FROM
        REAL_IP_HEADER = var.REAL_IP_HEADER
        LOG_IP_VAR = var.LOG_IP_VAR
        LIBRENMS_WEATHERMAP = var.LIBRENMS_WEATHERMAP
        LIBRENMS_SNMP_COMMUNITY = var.LIBRENMS_SNMP_COMMUNITY
        LIBRENMS_BASE_URL = var.LIBRENMS_BASE_URL
      }

      resources {
        memory = 512
      }
    }

    task "librenms-poller" {
      driver = "podman"

      config {
        image = var.librenms_image
        cap_add = ["NET_RAW","NET_ADMIN"]
        volumes = ["/mnt/services/librenms/config:/data"]        
        network_mode = "host"
        privileged = true
        logging = {
        driver = "journald"
        options = [
            {
            "tag" = "librenms-poller"
            }
          ]
        }         
      }

      env {
        TZ = var.TZ
        PUID = var.PUID
        PGID = var.PGID
        DB_HOST = var.DB_HOST
        DB_NAME = var.DB_NAME
        DB_USER = var.DB_USER
        DB_PASSWORD = var.DB_PASSWORD
        DB_TIMEOUT = var.DB_TIMEOUT
        REDIS_HOST = var.REDIS_HOST
        REDIS_DB = var.REDIS_DB
        REDIS_CACHE_DB = var.REDIS_CACHE_DB
        RRDCACHED_SERVER = var.RRDCACHED_SERVER
        CACHE_DRIVER = var.CACHE_DRIVER
        SESSION_DRIVER = var.SESSION_DRIVER
        MEMORY_LIMIT = var.MEMORY_LIMIT
        MAX_INPUT_VARS = var.MAX_INPUT_VARS
        UPLOAD_MAX_SIZE = var.UPLOAD_MAX_SIZE
        OPCACHE_MEM_SIZE = var.OPCACHE_MEM_SIZE
        DISPATCHER_NODE_ID = var.DISPATCHER_NODE_ID
        SIDECAR_DISPATCHER = var.SIDECAR_DISPATCHER
      }

      resources {
        memory = 512
      }
    }

    task "librenms-rrdcached" {
      driver = "podman"

      config {
        image = var.rrdcached_image
        ports = ["rrdcached"]
        volumes = ["/mnt/services/librenms/rrdcached/db:/data/db","/mnt/services/librenms/rrdcached/journal:/data/journal"]
        logging = {
        driver = "journald"
        options = [
            {
            "tag" = "librenms-rrdcached"
            }
          ]
        }         
      }

      env {
        TZ = "America/New_York"
        PUID = "2000"
        PGID = "2000"
        LOG_LEVEL = "LOG_INFO"
        WRITE_TIMEOUT = "1800"
        WRITE_JITTER = "1800"
        WRITE_THREADS = "4"
        FLUSH_DEAD_DATA_INTERVAL = "3600"
      }

      resources {
        memory = 512
      }      
    }
  }
}