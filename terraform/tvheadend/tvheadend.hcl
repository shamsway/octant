podman run --rm --name=tvheadend \
-p 9981:9981 \
-p 9982:9982 \
-e PUID=2000 \
-e PGID=2000 \
-v /mnt/services/tvheadend/config:/config \
-v /mnt/recordings/tvheadend/:/recordings \
--privileged \
lscr.io/linuxserver/tvheadend:latest

podman run -d --name=tvheadend \
-e PUID=2000 \
-e PGID=2000 \
-v /mnt/services/tvheadend/config:/config \
-v /mnt/recordings/tvheadend/:/recordings \
--privileged --network=host \
lscr.io/linuxserver/tvheadend:latest

// podman exec -it tvheadend /bin/bash

job "tvheadend" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "tvheadend" {
    count = 1

    volume "tvheadend-config" {
      type      = "host"
      read_only = false
      source    = "tvheadend-config"
    }

    volume "tvheadend-recordings" {
      type      = "host"
      read_only = false
      source    = "tvheadend-recordings"
    }

    network {
      port "http" {
        static = 9981
      }
      port "htsp" {
        static = 9982
      }
    }

    service {
      name = "tvheadend"
      port = "http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.tvheadend.rule=Host(`tvheadend.shamsway.net`)",
        "traefik.http.routers.tvheadend.entrypoints=web,websecure",
        "traefik.http.routers.tvheadend.tls.certresolver=cloudflare",
        "traefik.http.routers.tvheadend.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "tvheadend" {
      driver = "podman"      
      config {
        image = "docker.io/linuxserver/tvheadend"
        ports = ["http","htsp"]
      }

      env {
        PUID  = 2000
        PGID  = 2000
        TZ    = "America/New_York"
      }

      volume_mount {
        volume      = "tvheadend-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "tvheadend-recordings"
        destination = "/recordings"
        read_only   = false
      }      

      resources {
        cpu    = 500
        memory = 256
      }
     }
    }
  }
  