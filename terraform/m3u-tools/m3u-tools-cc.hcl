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

    network {
      port "http" { 
        to = 34400
      }

      #port "envoy" { 
      #  to = 19001
      #}

      port "metrics" { 
        to = 9102
      }
      
      port "gluetun" { 
        to = 8000
      }

      port "vpnhealth" { 
        to = 9999
      }                  
      
      mode = "bridge"
    }

    service {
      name = "metrics"
      port = "metrics"
      provider = "consul"
      tags = ["metrics"]
    }
    
    # service {
    #  name = "envoy"
    #  port = "envoy"
    #  provider = "consul"
    #  tags = ["admin"]
    # }       

    service {
      name = "gluetun"
      port = "gluetun"
      provider = "consul"
      task = "gluetun"   
      tags = [
        "admin",
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.gluetun.rule=Host(`gluetun.shamsway.net`)",
        "traefik.http.routers.gluetun.entrypoints=web,websecure",   
        "traefik.http.routers.gluetun.tls.certresolver=cloudflare",
        "traefik.http.services.gluetun.loadbalancer.server.scheme=http",
      ]
      connect {
        native = true
        }
      }
    
    service {
      name = "xteve"
      port = 34400
      task = "xteve"
      provider = "consul"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.xteve.rule=Host(`xteve.shamsway.net`)",
        "traefik.http.routers.xteve.entrypoints=web,websecure",   
        "traefik.http.routers.xteve.tls.certresolver=cloudflare",
        #"traefik.http.services.xteve.loadbalancer.server.port=${NOMAD_HOST_PORT_http}",
        "traefik.http.services.xteve.loadbalancer.server.scheme=http",
        "traefik.http.services.xteve.tls"
      ]
      connect {
      	#native = true
        sidecar_service {
          proxy { }
        }
      }
    }    
    
    task "xteve" {
      driver = "podman"

      resources {
        cores = 1
      }

      volume_mount {
        volume      = "xteve"
        destination = "/config"
      }
      
      config {
        image  = "alturismo/xteve"
        volumes = ["local/:/tmp/xteve:rw"]
        privileged = true
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
      
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }      

      resources {
        memory = 512
      }

      service {
        name = "vpnhealth"
        port = "vpnhealth"
        provider = "consul"
        tags = ["healthcheck"]
        check {
            name     = "alive"
            type     = "tcp"
            #path     = "/health/liveliness"
            interval = "60s"
            timeout  = "5s"
        }        
      }

      config {
        image      = "qmcgaw/gluetun"
        cap_add    = ["NET_ADMIN","SYS_ADMIN"]
        devices    = ["/dev/net/tun"]
        volumes    = ["local/wg0.conf:/gluetun/wireguard/wg0.conf"]
        ports      = ["vpnhealth"]
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
        FIREWALL_OUTBOUND_SUBNETS = "192.168.252.0/24"
        HTTP_CONTROL_SERVER       = ":8000"
        HEALTH_SERVER_ADDRESS     = ":9999"
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
    }    
  }    
}