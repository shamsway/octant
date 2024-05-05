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

  group "iptv" {
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
      mode = "bridge"        
      #port "envoy" { to = 19001 }
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
      port "xteve" { 
        to = 34400 
      }      
      port "metrics" { to = 9102 }
      port "gluetun" { to = 8000 }
      port "vpnhealth" { to = 9999 }                  

      dns {
        servers = ["192.168.252.1","192.168.252.7"]
      }      
    }

    service {
      name = "envoy-metrics"
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
      name = "tvheadend"
      port = 9981
      task = "tvheadend"      
      provider = "consul"

      connect {
          native = true
      }   

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
        "traefik.http.services.tvheadend.tls"
    ]      
    }

    service {
      name = "tvh-htsp-1"
      port = 9982
      task = "tvheadend"      
      provider = "consul"

    connect {
      native = true
    }

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
      name = "tvh-htsp-2"
      port = 9983
      task = "tvheadend"      
      provider = "consul"

      connect {
          native = true
      }
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
      name = "tvh-htsp-3"
      port = 9984
      task = "tvheadend"      
      provider = "consul"

      connect {
          native = true
      }

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
      name = "tvh-htsp-3"
      port = 9985
      task = "tvheadend"      
      provider = "consul"

      connect {
          native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.tcp.routers.htsp3.rule=HostSNI(`*`)",
        "traefik.tcp.routers.htsp3.service=htsp4",
        "traefik.http.routers.htsp3.entrypoints=hts4",
        "traefik.http.routers.htsp3.loadbalancer.server.port=9985"        
      ]       
    }

    service {
      name = "xteve"
      port = 34400
      task = "xteve"
      provider = "consul"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.xteve.rule=Host(`xteve.shamsway.net`) || Host(`xteve.service.consul`)",
        "traefik.http.routers.xteve.entrypoints=web,http,websecure",   
        "traefik.http.routers.xteve.tls.certresolver=cloudflare",
        "traefik.http.services.xteve.loadbalancer.server.scheme=http",
        "traefik.http.services.xteve.tls"
      ]
      connect {
        native = true
      }
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

    task "gluetun" {
    driver = "podman"
    
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }      

      resources {
        memory = 768
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