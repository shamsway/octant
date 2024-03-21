job "traefik" {
  datacenters = ["shamsway"]
  type        = "service"

  group "traefik" {
    count = 1

    network {
      port  "http" {
         static = 80
      }
      port  "admin" {
         static = 8080
      }
    }

    service {
      name = "traefik-http"
      provider = "consul"
      port = "http"
    }

    task "server" {
      driver = "podman"
      config {
        image = "docker.io/traefik:2.11"
        ports = ["admin", "http"]
        args = [
          "--api.dashboard=true",
          "--api.insecure=true", ### For Test only, please do not use that in production
          "--entrypoints.web.address=:${NOMAD_PORT_http}",       
          "--entrypoints.traefik.address=:${NOMAD_PORT_admin}",
          "--providers.nomad=true",
          "--providers.nomad.endpoint.address=http://192.168.252.6:4646", ### IP to your nomad server 
          "--providers.consulcatalog=true",
          "--providers.consulcatalog.prefix=traefik",
          "--providers.consulcatalog.endpoint.address=192.168.252.6:8500",
          "--providers.consulcatalog.endpoint.datacenter=shamsway",
          "--providers.consulcatalog.endpoint.scheme=http",
          "--providers.consulcatalog.serviceName=traefik",
          "--providers.consulcatalog.exposedByDefault=false",
          "--providers.consulcatalog.defaultRule=Host(Host(`{{ .Name }}.service.shamsway.consul`))",
          "--log.level=INFO",
          "--log.format=json",
          "--accesslog=true",
          "--accesslog.format=json",
          "--accesslog.fields.defaultmode=keep",
          "--accesslog.fields.names.ClientUsername=drop",
          "--accesslog.fields.headers.defaultmode=keep",
          "--accesslog.fields.headers.names.User-Agent=redact",
          "--accesslog.fields.headers.names.Authorization=drop",
          "--tracing.serviceName=traefik",
          "--tracing.spanNameLimit=250",          
        ]

        volumes = [
          "local/traefik.toml:/etc/traefik/traefik.toml",
          "local/acme:/etc/traefik/acme",
        ]        
      }

      logs {
        max_files     = 10
        max_file_size = 20
      }      
    }
  }
}