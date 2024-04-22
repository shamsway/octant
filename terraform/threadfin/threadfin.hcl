job "threadfin" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "threadfin" {
    volume "threadfin" {
      type      = "host"
      read_only = false
      source    = "threadfin"
    }

    affinity {
      attribute = "${node.unique.name}"
      value     = "jerry"
      weight    = 100
    }

    network {
      mode = "bridge"
      port "http" {
        static = 34400
      }
    }

    service {
      name = "threadfin"
      provider = "consul"
      port = "http"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "threadfin"
              local_bind_port  = 34400
            }
          }
        }
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

    task "threadfin" {
      driver = "podman"
      volume_mount {
        volume      = "threadfin"
        destination = "/home/threadfin/conf"
      }
      config {
        image        = "fyb3roptik/threadfin"
        network_mode = "container:gluetun-${NOMAD_ALLOC_ID}"
        volumes      = ["local/:/tmp/xteve:rw"]
      }
      env {
        PUID = "2000"
        PGID = "2000"
        TZ   = "America/New_York"
      }
      service {
        name = "threadfin"
        port = "http"
        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}