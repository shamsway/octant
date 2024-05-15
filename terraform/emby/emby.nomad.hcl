job "embyserver" {
  datacenters = ["shamsway"]
  type = "service"

  constraint {
    attribute = "${meta.rootless}"
    value     = "false"
  }

  constraint {
    attribute = "${node.unique.name}"
    value = "bobby-agent-root"
  }

  group "embyserver" {
    affinity {
      attribute = "${node.unique.name}"
      value     = "bobby-root"
      weight    = 100
    }

    network {
      port "http" {
        static = 8096
      }

      port "https" {
        static = 8920
      }

      dns {
        servers = ["192.168.252.1","192.168.252.7"]
      }         
    }

    volume "emby-config" {
      type      = "host"
      read_only = false
      source    = "emby-config"
    }

    volume "media-library" {
      type      = "host"
      read_only = false
      source    = "media-library"
    }

    volume "tvheadend-recordings" {
      type      = "host"
      read_only = false
      source    = "tvheadend-recordings"
    }    

    service {
      name = "embyserver"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.embyserver.rule=Host(`embyserver.shamsway.net`)",
        "traefik.http.routers.embyserver.entrypoints=web,websecure",
        "traefik.http.routers.embyserver.tls.certresolver=cloudflare",
        "traefik.http.routers.embyserver.middlewares=redirect-web-to-websecure@internal",
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

    task "embyserver" {
      driver = "podman"

      config {
        image = "docker.io/emby/embyserver:latest"
        force_pull = true
        ports = ["http", "https"]
        devices = ["/dev/dri"]
        logging {
          driver = "journald"
          options = [
            {
              "tag" = "embyserver"
            }
          ]
        }
      }

      volume_mount {
        volume      = "emby-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "media-library"
        destination = "/mnt/library"
        read_only   = false
      }      

      volume_mount {
        volume      = "tvheadend-recordings"
        destination = "/mnt/recordings"
        read_only   = false
      }

      env {
        UID     = "2000"
        GID     = "2000" 
        GIDLIST = "45,105"
      }

      resources {
        cores  = 2
        memory = 1024
      }
    }
  }
}