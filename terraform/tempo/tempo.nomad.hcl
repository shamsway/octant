job "tempo" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "tempo" {
    network {
      port "http" {
        static = 3200
        to     = 3200
      }

      port "otlp_grpc" {
        static = 4317
        to     = 4317
      }

      port "otlp_http" {
        static = 4318
        to     = 4318
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      task     = "tempo"
      port     = "http"
      provider = "consul"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
        "homepage.group=Observability",
        "homepage.name=Tempo",
        "homepage.icon=tempo",
        "homepage.description=Distributed Tracing",
      ]

      check {
        name     = "ready"
        type     = "http"
        path     = "/ready"
        interval = "20s"
        timeout  = "5s"
      }
    }

    task "tempo" {
      user   = "10001:10001"
      driver = "podman"

      config {
        image  = "${image}"
        userns = "keep-id:uid=10001,gid=10001"
        args = [
          "-config.file=/etc/tempo/tempo.yaml",
        ]
        ports = ["http", "otlp_grpc", "otlp_http"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
        volumes = [
          "/mnt/services/tempo:/var/tempo",
          "local/tempo.yaml:/etc/tempo/tempo.yaml",
        ]
      }

      template {
        destination = "local/tempo.yaml"
        change_mode = "signal"
        change_signal = "SIGHUP"
        data        = <<EOH
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

ingester:
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 168h

storage:
  trace:
    backend: local
    wal:
      path: /var/tempo/wal
    local:
      path: /var/tempo/traces
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
