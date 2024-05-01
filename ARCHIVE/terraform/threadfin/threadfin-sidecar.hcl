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
        native = true
      }          

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.threadfin.rule=Host(`threadfin.shamsway.net`)",
        "traefik.http.routers.threadfin.entrypoints=web,websecure",
        "traefik.http.routers.threadfin.tls.certresolver=cloudflare",
        "traefik.http.routers.threadfin.middlewares=redirect-web-to-websecure@internal",
        "traefik.http.services.threadfin.loadbalancer.server.port=${NOMAD_HOST_PORT_http}"        
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
      port "http" { static = 34400 }
      mode = "bridge"
    }

    task "threadfin" {
      driver = "podman"
      user   = "31337"

      resources {
        cores = 2
      }

      volume_mount {
        volume      = "threadfin"
        destination = "/home/threadfin/conf"
      }

      config {
        image  = "fyb3roptik/threadfin"
		    #userns = "keep-id:uid=31337,gid=31337"
        #network_mode = "container:gluetun-${NOMAD_ALLOC_ID}"
        volumes = ["local/:/tmp/xteve:rw"]
        ports = ["http"]
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
        TZ   = "America/New_York"
        THREADFIN_DEBUG = "2"
        THREADFIN_LOG = "/home/threadfin/conf/threadfin.log"
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
        VPN_TYPE                  = "wireguard"
        VPN_SERVICE_PROVIDER      = "custom"
        WIREGUARD_IMPLEMENTATION  = "userspace"
        FIREWALL_OUTBOUND_SUBNETS = "192.168.252.0/24,10.88.0.1/16"
        HTTP_CONTROL_SERVER       = ":8000" 
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