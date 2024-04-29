job "m3u-tools" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "${meta.rootless}"
    value = "false"
  }

  group "m3u-tools" {
    volume "xteve" {
      type      = "host"
      read_only = false
      source    = "xteve"
    }

    affinity {
      attribute = "${node.unique.name}"
      value     = "bobby-root"
      weight    = 100
    }

    service {
      name = "xteve"
      port = "http"
      task = "xteve"
      provider = "consul" 

      connect {
        #sidecar_service { }
        native = true
      }          

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.xteve.rule=Host(`xteve.shamsway.net`)",
        "traefik.http.routers.xteve.entrypoints=web,websecure",
        "traefik.http.routers.xteve.tls.certresolver=cloudflare",
        "traefik.http.routers.xteve.middlewares=redirect-web-to-websecure@internal",
        #"traefik.http.services.xteve.loadbalancer.server.port=${NOMAD_HOST_PORT_http}"        
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "60s"
        timeout  = "10s"
      }        
    }

    network {
      port "http" { 
        static = 34400 
        to = 34400
      }
      mode = "bridge"
    }

    task "xteve" {
      driver = "podman"

      resources {
        cores = 2
      }

      volume_mount {
        volume      = "xteve"
        destination = "/config"
      }

      config {
        image  = "alturismo/xteve"
        volumes = ["local/:/tmp/xteve:rw"]
        ports = ["http"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "xteve"
            }
          ]
        }        
      }

      env {
        TZ   = "America/New_York"
      }
    }
    
    task "gluetun" {
      driver = "podman"
      config {
        image      = "qmcgaw/gluetun"
        cap_add    = ["NET_ADMIN","SYS_ADMIN"]
        devices    = ["/dev/net/tun"]
        volumes    = ["local/wg0.conf:/gluetun/wireguard/wg0.conf"]
        privileged = true
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "gluetun"
            }
          ]
        }        
      }
      env {
        VPN_TYPE                 = "wireguard"
        VPN_SERVICE_PROVIDER     = "custom"
        WIREGUARD_IMPLEMENTATION = "userspace"
      }
      template {
        data = <<EOH
[Interface]
# Key for gluetun
# Bouncing = 1
# NetShield = 1
# Moderate NAT = off
# NAT-PMP (Port Forwarding) = off
# VPN Accelerator = on
PrivateKey = IFlrcEPSAhcWrkSm0bKHQYz8eTRTtJw557T7lO/25GU=
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
# US-NY#25
PublicKey = R8Of+lrl8DgOQmO6kcjlX7SchP4ncvbY90MB7ZUNmD8=
AllowedIPs = 0.0.0.0/0
Endpoint = 193.148.18.82:51820
EOH
        destination = "local/wg0.conf"
      }

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }
    }    
  }
}