job "librenms" {
  region = "home"
  datacenters = ["shamsway"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "${meta.rootless}"
    value = "false"
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
      port "rrdcached" {
        static = 42217
        to = 42217
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

    volume "librenms-data" {
      type      = "host"
      read_only = false
      source    = "librenms-data"
    }

    service {
      name = "librenms"
      provider = "consul"
      task = "librenms"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.librenms.rule=Host(`librenms.shamsway.net`)",
        "traefik.http.routers.librenms.entrypoints=web,websecure",
        "traefik.http.routers.librenms.tls.certresolver=cloudflare",
        "traefik.http.routers.librenms.middlewares=redirect-web-to-websecure@internal",
      ]

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
      #user = "librenms"

      config {
        image = "docker.io/librenms/librenms:24.4.1"
        ports = ["http"]
        cap_add = ["NET_RAW","NET_ADMIN"]  
        #userns = "keep-id:uid=1000,gid=1000"
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
        PUID = "2000"
        PGID = "2000"
        DB_HOST = "mariadb.service.consul"
        DB_NAME = "librenms"
        DB_USER = "librenms"
        DB_PASSWORD = "As3cur3P@ssw0rd!"
        DB_TIMEOUT = "60"
        REDIS_HOST = "redis.service.consul"
        REDIS_DB = "2"
        REDIS_CACHE_DB = "3"
        CACHE_DRIVER = "redis"
        SESSION_DRIVER = "redis"
        RRDCACHED_SERVER = "rrdcached.service.consul:42217"
        MEMORY_LIMIT = "256M"
        MAX_INPUT_VARS = "1000"
        UPLOAD_MAX_SIZE = "16M"
        OPCACHE_MEM_SIZE = "128"
        REAL_IP_FROM = "0.0.0.0/32"
        REAL_IP_HEADER = "X-Forwarded-For"
        LOG_IP_VAR = "http_x_forwarded_for"       
        LIBRENMS_WEATHERMAP = "true"
        LIBRENMS_SNMP_COMMUNITY = "shamsway"
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

    task "librenms-poller" {
      driver = "podman"
      #user = "librenms"

      config {
        image = "docker.io/librenms/librenms:24.4.1"
        cap_add = ["NET_RAW","NET_ADMIN"] 
        network_mode = "host"
        privileged = true
        #userns = "keep-id:uid=1000,gid=1000"
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
        TZ = "America/New_York"
        PUID = "2000"
        PGID = "2000"
        DB_HOST = "mariadb.service.consul"
        DB_NAME = "librenms"
        DB_USER = "librenms"
        DB_PASSWORD = "As3cur3P@ssw0rd!"
        DB_TIMEOUT = "60"
        REDIS_HOST = "redis.service.consul"
        REDIS_DB = "2"
        REDIS_CACHE_DB = "3"
        RRDCACHED_SERVER = "rrdcached.service.consul:42217"
        CACHE_DRIVER = "redis"
        SESSION_DRIVER = "redis"
        MEMORY_LIMIT = "256M"
        MAX_INPUT_VARS = "1000"
        UPLOAD_MAX_SIZE = "16M"
        OPCACHE_MEM_SIZE = "128"   
        DISPATCHER_NODE_ID = "dispatcher"
        SIDECAR_DISPATCHER = "1"
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

    task "librenms-rrdcached" {
      driver = "podman"
      #user = "librenms"

      config {
        image = "docker.io/crazymax/rrdcached:1.8.0-r5"
        #userns = "keep-id:uid=1000,gid=1000"
        ports = ["rrdcached"]
        volumes = ["/mnt/services/librenms/config/rrd/db:/data/db","/mnt/services/librenms/config/rrd/journal:/data/journal"]
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
        memory = 256
      }      
    }
  }
}