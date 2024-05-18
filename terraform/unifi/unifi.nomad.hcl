job "unifi" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "false"
  }

  constraint {
    attribute = "${node.unique.name}"
    value = "bobby-agent-root"
  }

  group "unifi" {
    network {
      port "http" {
        static = 8080
        to = 8080
       }
      port "https" { 
        static = 4443
        to = 4443
      }
      port "stun" {
        static = 3478
        to = 3478
      }
      port "discovery" {
        static = 10001
        to = 10001
      }
      port "unifi-discovery" {
        static = 1900
        to = 1900
      }
      port "remote-syslog" {
        static = 5514
        to = 5514
      }
      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
      }
    }

    volume "unifi-config" {
      type      = "host"
      read_only = false
      source    = "unifi-config"
    }

    volume "unifi-data" {
      type      = "host"
      read_only = false
      source    = "unifi-data"
    }    

    volume "backups" {
      type      = "host"
      read_only = false
      source    = "backups"
    }    

    service {
      name = "unifi"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.unifi-network-application.rule=Host(`unifi.shamsway.net`)",
        "traefik.http.routers.unifi-network-application.entrypoints=web,websecure",
        "traefik.http.routers.unifi-network-application.tls.certresolver=cloudflare",
        "traefik.http.routers.unifi-network-application.middlewares=redirect-web-to-websecure@internal",
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

    task "unifi" {
      driver = "podman"
      #user = "unifi"

      config {
        image = "docker.io/jacobalberty/unifi:v8.1.113"
        network_mode = "host"
        privileged = "true"
        #userns = "keep-id:uid=999,gid=999"
        ports = ["http", "https", "stun", "discovery", "unifi-discovery", "remote-syslog"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "unifi"
            }
          ]
        }
      }

      volume_mount {
        volume      = "unifi-data"
        destination = "/unifi/data"
        read_only   = false
      }

      volume_mount {
        volume           = "backups"
        propagation_mode = "host-to-task"
        destination      = "${NOMAD_TASK_DIR}/backup"
        read_only        = false
      }      

      env {
        PUID              = "2000"
        PGID              = "2000"
        TZ                = "Amercica/New_York"
        UNIFI_HTTP_PORT   = NOMAD_PORT_http
        UNIFI_HTTPS_PORT  = NOMAD_PORT_https
        UNIFI_STDOUT      = true 
      }

      resources {
        memory = 768
      }
    }
  }
}