job "iptv" {
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

  constraint {
      attribute = "${node.unique.name}"
      value = "bobby-agent-root"
  }

  group "xteve" {
    network {
      mode = "bridge"

      port "xteve" {  
        to = 34400
      }       

      dns {
        servers = ["192.168.252.1","192.168.252.7"]
      }           
    }     

    service {
      name = "xteve"
      port = "xteve"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.xteve.rule=Host(`xteve.shamsway.net`) || Host(`xteve.service.consul`)",
        "traefik.http.routers.xteve.entrypoints=web,http,websecure",   
        "traefik.http.routers.xteve.tls.certresolver=cloudflare",
        "traefik.http.services.xteve.loadbalancer.server.scheme=http",
      ]
      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "gluetun"
              local_bind_port  = 1111
            }
          }
        }
      }    
    }

    volume "xteve" {
      type      = "host"
      read_only = false
      source    = "xteve"
    }

    volume "tvheadend-config" {
      type      = "host"
      read_only = false
      source    = "tvheadend-config"
    }

    task "xteve" {
      driver = "podman"

      resources {
        memory = 768
      }
    
      volume_mount {
        volume      = "xteve"
        destination = "/root/.xteve"
        read_only   = false
      }

      volume_mount {
        volume      = "xteve"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
          volume      = "tvheadend-config"
          destination = "/TVH"
          read_only   = true
      }

      config {
        image  = "alturismo/xteve"
        volumes = ["local/:/tmp/xteve:rw"]
        network_mode = "container:gluetun-${NOMAD_ALLOC_ID}"
        ports = ["xteve"]
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
  }

  group "tvheadend" {
    volume "tvheadend-config" {
      type      = "host"
      read_only = false
      source    = "tvheadend-config"
    }

    volume "tvheadend-data" {
      type      = "host"
      read_only = false
      source    = "tvheadend-data"
    }

    volume "tvheadend-recordings" {
      type      = "host"
      read_only = false
      source    = "tvheadend-recordings"
    }    

    network {
      port "http" { 
        static = 9981 
        to = 9981 
      }
      port "htsp-2" { 
        static = 9982 
        to = 9982 
      }
      port "htsp-3" { 
        static = 9983 
        to = 9983 
      }
      port "htsp-4" { 
        static = 9984 
        to = 9984
      }
      port "htsp-5" { 
        static = 9985 
        to = 9985
      }
      port "htsp-6" { 
        static = 9986 
        to = 9986 
      }
      port "htsp-7" { 
        static = 9987 
        to = 9987 
      }
      port "htsp-8" { 
        static = 9988 
        to = 9988
      }    

      port "gluetun" { to = 8000 }
      port "vpnhealth" { to = 9999 }                  

      dns {
        servers = ["192.168.252.1","192.168.252.7"]
      }      
    }        
    
    task "tvheadend" {
      driver = "podman"

      resources {
        cores = 1
        memory = 512
      }

      config {
        image = "docker.io/linuxserver/tvheadend"
        ports = ["http","htsp-2","htsp-3","htsp-4","htsp-5","htsp-6","htsp-7","htsp-8"]
        privileged = true
        logging = {
          driver = "journald"
          options = [
            {
            "tag" = "tvheadend"
            }
          ]
        }          
      }

      service {
        name = "tvheadend"
        port = "http"  
        provider = "consul"

        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }

        tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",
          "traefik.http.routers.tvheadend.rule=Host(`tvheadend.shamsway.net`) || Host(`tvheadend.service.consul`)",
          "traefik.http.routers.tvheadend.entrypoints=web,http,websecure",   
          "traefik.http.routers.tvheadend.tls.certresolver=cloudflare",
          "traefik.http.services.tvheadend.loadbalancer.server.scheme=http",
        ]      
      }

      service {
        name = "tvh-htsp-2"
        port = "htsp-2"
        provider = "consul"

      tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",          
          "traefik.tcp.routers.htsp1.rule=HostSNI(`*`)",
          "traefik.tcp.routers.htsp1.service=htsp1",
          "traefik.http.routers.htsp1.entrypoints=htsp1",
          "traefik.http.routers.htsp1.loadbalancer.server.port=9982"        
        ]      
      }

      service {
        name = "tvh-htsp-3"
        port = "htsp-3"
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",          
          "traefik.tcp.routers.htsp2.rule=HostSNI(`*`)",
          "traefik.tcp.routers.htsp2.service=htsp2",
          "traefik.http.routers.htsp2.entrypoints=htsp2",
          "traefik.http.routers.htsp2.loadbalancer.server.port=9983"        
        ]        
      }

      service {
        name = "tvh-htsp-4"
        port = "htsp-4"    
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",          
          "traefik.tcp.routers.htsp3.rule=HostSNI(`*`)",
          "traefik.tcp.routers.htsp3.service=htsp3",
          "traefik.http.routers.htsp3.entrypoints=htsp3",
          "traefik.http.routers.htsp3.loadbalancer.server.port=9984"        
        ] 
      }

      service {
        name = "tvh-htsp-5"
        port = "htsp-5"      
        provider = "consul"

        tags = [
          "traefik.enable=true",
          "traefik.consulcatalog.connect=false",          
          "traefik.tcp.routers.htsp3.rule=HostSNI(`*`)",
          "traefik.tcp.routers.htsp3.service=htsp4",
          "traefik.http.routers.htsp3.entrypoints=hts4",
          "traefik.http.routers.htsp3.loadbalancer.server.port=9985"        
        ]       
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
          volume      = "tvheadend-data"
          destination = "/data"
          read_only   = false
      }      

      volume_mount {
          volume      = "tvheadend-recordings"
          destination = "/recordings"
          read_only   = false
      }          
    }
  }

  group "gluetun" {
    network {
      mode = "bridge"
      port "gluetun" { to = 8000 }
      port "vpnhealth" { to = 9999 }                  

      dns {
        servers = ["192.168.252.1","192.168.252.7"]
      }                       
    } 

    service {
      name = "vpnhealth"
      port = "vpnhealth"
      provider = "consul"
      tags = ["healthcheck"]
      check {
        name     = "alive"
        type     = "tcp"
        interval = "60s"
        timeout  = "5s"
      }        
    }

    service {
      name = "gluetun"
      port = "gluetun"
      provider = "consul"   
      tags = [
        "admin",
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.gluetun.rule=Host(`gluetun.shamsway.net`)",
        "traefik.http.routers.gluetun.entrypoints=web,websecure",   
        "traefik.http.routers.gluetun.tls.certresolver=cloudflare",
        "traefik.http.services.gluetun.loadbalancer.server.scheme=http",
      ]
    }

    service {
      name = "xteve"
      port = 1111

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "app1"
              local_bind_port  = 34400
            }
          }
        }
      }
    }

    task "gluetun" {
      driver = "podman" 

      resources {
        memory = 768
      }

      config {
        image      = "qmcgaw/gluetun"
        cap_add    = ["NET_ADMIN","SYS_ADMIN"]
        devices    = ["/dev/net/tun"]
        volumes    = ["local/wg0.conf:/gluetun/wireguard/wg0.conf"]
        ports      = ["gluetun","vpnhealth"]
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