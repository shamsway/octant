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

  group "ingress" {
    network {
      mode = "bridge"

      # This example will enable plain HTTP traffic to access the uuid-api connect
      # native example service on port 8080.
      # port "inbound" {
      #   static = 8080
      #   to     = 8080
      # }
    } 

    service {
      name = "ingress"
      port = 34401

      connect {
        gateway {
          proxy { }
          ingress {
            listener { 
              protocol = "tcp"
              port = 34401
              service {
                name = "threadfin"
              }
            }
          }
        }
      }      
    }
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

    network {
      mode = "bridge"

      port "http" { to = 34400 }
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
      user   = "2000"

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
        connect {
          native = true
        }
      }
    }
  }
}

#####
from claude

group "ingress" {
  network {
    mode = "bridge"
  }

  service {
    name = "ingress"
    port = 34401

    connect {
      sidecar_task {
        driver = "podman"
      }

      gateway {
        proxy {
        }

        ingress {
          listener {
            port     = 34401
            protocol = "tcp"
            
            service {
              name = "threadfin"
            }
          }
        }
      }
    }
  }
}


#####

snip

  group "ingress" {
    network {
      mode = "bridge"

      # This example will enable plain HTTP traffic to access the uuid-api connect
      # native example service on port 8080.
      # port "inbound" {
      #   static = 8080
      #   to     = 8080
      # }
    } 

    service {
      name = "ingress"
      port = 34401    
      
      connect {
        sidecar_task { driver = "podman" }          
        gateway {
          proxy { }
          ingress {
            listener { 
              protocol = "tcp"
              port = 34401
              service {
                name = "threadfin"
              }
            }
          }
        }
      }      
    }
  }