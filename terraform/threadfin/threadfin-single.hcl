job "threadfin" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "${node.unique.name}"
    operator  = "regexp"
    value     = "-root$"
  } 

  group "threadfin" {
    volume "threadfin" {
      type      = "host"
      read_only = false
      source    = "threadfin"
    }

    affinity {
      attribute = "${node.unique.name}"
      value     = "bobby-root"
      weight    = 100
    }

    service {
      name = "threadfin"
      port = "http"
      task = "threadfin"
      provider = "consul" 

      connect {
        sidecar_service {}
        sidecar_task {
        name = "connect-proxy-threadfin"

        driver = "podman"

        config {
            image = "${meta.connect.sidecar_image}"
            #       "${meta.connect.gateway_image}" when used as a gateway

            args = [
            "-c",
            "${NOMAD_SECRETS_DIR}/envoy_bootstrap.json",
            "-l",
            "${meta.connect.log_level}",
            "--concurrency",
            "${meta.connect.proxy_concurrency}",
            "--disable-hot-restart"
            ]
          }    
        }
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.threadfin.rule=Host(`threadfin.shamsway.net`)",
        "traefik.http.routers.threadfin.entrypoints=web,websecure",
        "traefik.http.routers.threadfin.tls.certresolver=cloudflare",
        "traefik.http.routers.threadfin.middlewares=redirect-web-to-websecure@internal",
        "traefik.http.services.threadfin.loadbalancer.server.port=${NOMAD_HOST_PORT_http}",         
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/web"
        interval = "10s"
        timeout  = "2s"
      }        
    }

    network {
      port "http" { to = 34400 }
      mode = "bridge"
    }

    task "threadfin" {
      driver = "podman"
      #user   = "2000"

      volume_mount {
        volume      = "threadfin"
        destination = "/home/threadfin/conf"
      }

      config {
        image  = "fyb3roptik/threadfin"
		userns = "keep-id:uid=31337,gid=31337"
        #network_mode = "container:gluetun-${NOMAD_ALLOC_ID}"
        volumes      = ["local/:/tmp/xteve:rw"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "threadfin"
            }
          ]
        }        
      }

      env {
        PUID = "2000"
        PGID = "2000"
        TZ   = "America/New_York"
      }
    }
  }
}