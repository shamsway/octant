job "traefik" {
  region = "home"
  datacenters = ["shamsway"]
  type = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  meta {
    version = "1"
  }

  group "lbs" {
    count = 1
    network {
      port "http" {
        static = "80"
      }
      port "https" {
        static = "443"
      }
      port "api" {
        static = "8080"
      }
      port "metrics" {
        static = "8082"
      }
      port "admin" {
        static = "9002"
      }
    }

    update {
      max_parallel     = 1
      min_healthy_time = "30s"
      auto_revert      = true
    }

    volume "traefik-data" {
      type      = "host"
      read_only = false
      source		= "traefik-data"
    }  

    service {
      name = "traefik-http"
      port = "http"
      tags = [
        "traefik",
        "traefik.enable=true",
        "traefik.http.routers.dashboard.rule=Host(`traefik-http.shamsway.net`)",
        "traefik.http.routers.dashboard.service=api@internal",
        "traefik.http.routers.dashboard.entrypoints=web,websecure",
      ]
      check {
        name     = "alive"
        type     = "tcp"
        port     = "http"
        interval = "10s"
        timeout  = "5s"
      }
    }

    service {
      name = "traefik"
      port = "https"
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "5s"
      }
    }

    service {
      name = "traefik-admin"
      provider = "consul"
      port = "admin"
      check {
        name     = "alive"
        type     = "http"
        port     = "admin"
        path     = "/ping"
        interval = "10s"
        timeout  = "2s"
      }
      tags = [
        "traefik","traefik.enable=true","lb", "admin",
        "traefik.http.routers.dashboard.rule=Host(`traefik.shamsway.net`)"
        #"metrics",
        #"metrics_port=8082",
        #"metrics_scheme=http",
        #"metrics_path=/metrics",
        #"traefik.tags=clusterservice",
        #"traefik.consulcatalog.connect=false",
        #"traefik.http.routers.metrics.rule=PathPrefix(`/metrics`)",
        #"traefik.http.routers.metrics.entrypoints=api",
        #"traefik.http.routers.metrics.service=prometheus@internal",
        #"traefik.http.routers.api.rule=(PathPrefix(`/api`) || PathPrefix(`/dashboard`))",
        #"traefik.http.routers.api.entrypoints=api",
        #"traefik.http.routers.api.service=api@internal",
        #"traefik.http.routers.api.middlewares=AdminAuth@file"
      ]
      connect {
        native = true
      }
    }

    task "traefik" {
      driver = "podman"

      volume_mount {
        volume      = "traefik-data"
        destination = "/acme"
        read_only   = false
      }

      config {
        image = "docker.io/traefik:v3.0"
        args  = ["--configFile", "/etc/traefik/traefik.toml"]
        ports = ["http", "https", "api", "metrics", "admin"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "traefik"
            }
          ]
        }
        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml",
          #"/acme/acme.json:/acme.json"
        ]
      }

      env {
        CLOUDFLARE_EMAIL = "mattadamelliott@gmail.com"
        CLOUDFLARE_API_KEY = "b0f9feb2cfce1ba2618dc83e17285682fd44e"
      }

      service {
        name = "traefik-metrics"
        tags = ["lb", "exporter", "metrics", "prometheus.scrape"]
        provider = "consul"
        port = "metrics"
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "5s"
          path     = "/ping"
        }
      }

      template {
data = <<EOH
[global]
  checkNewVersion = false
  sendAnonymousUsage = false
[metrics]
  [metrics.prometheus]
    entrypoint = "metrics"
[entryPoints]
  [entryPoints.web]
    address = ":80"
    [entryPoints.web.http.redirections.entryPoint]
	  to = "websecure"
      scheme = "https"
  [entryPoints.traefik]
    address = ":9002"
  [entryPoints.websecure]
    address = ":443"
  [entryPoints.metrics]
    address = ":8082"    
[accessLog]
  format = "json"
  filePath = "/acme/traefik-access.log"
[http.middlewares]
  [http.middlewares.https-redirect.redirectscheme]
    scheme = "https"
[certificatesResolvers.cloudflare.acme]
  email = "mattadamelliott@gmail.com"
  storage = "/acme/acme.json"
  [certificatesResolvers.cloudflare.acme.dnsChallenge]
    provider = "cloudflare"
    delayBeforeCheck = 30
    resolvers = ["1.1.1.1:53", "8.8.8.8:53"]
[log]
  #level = "INFO"
  level = "DEBUG"
  filePath = "/acme/traefik.log"
[api]
  dashboard = true
  insecure = true
[ping]
[providers]
  [providers.file]
    filename = "local/dynamic.toml"  
[providers.consulcatalog]
  exposedByDefault = false
  prefix = "traefik"
  defaultRule = "Host(`{{ .Name }}.shamsway.net`)"
  connectAware = true
  connectByDefault = true        
  [providers.consulcatalog.endpoint]
    address = "consul.shamsway.net:8501"
    scheme = "https"
    datacenter = "shamsway"
    endpointWaitTime = "15s"
    [tls]
      insecureskipverify = true
      ca = "/acme/consul-agent-ca.pem"
      certFile = "/acme/shamsway-server-traefik-1.pem"
      keyFile  = "/acme/shamsway-server-traefik-1-key.pem"      
EOH
        destination = "local/traefik.toml"
      }

      template {
       data        = <<EOH
[[tls.certificates]]
    certFile = "/acme/shamsway-server-traefik-1.pem"
    keyFile  = "/acme/shamsway-server-traefik-1-key.pem"
[tls.stores]
  [tls.stores.default]
    [tls.stores.default.defaultCertificate]
      certFile = "/acme/shamsway-server-traefik-1.pem"
      keyFile  = "/acme/shamsway-server-traefik-1-key.pem"
EOH
       destination = "local/dynamic.toml"
       change_mode = "restart"
       splay       = "1m"
     }

      resources {
        memory = 128
      }

      logs {
        max_files     = 10
        max_file_size = 20
      }
    }
  }
}