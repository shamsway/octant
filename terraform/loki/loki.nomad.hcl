job "loki" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "loki" {
    count = 1

    network {
      port "http" {
        static = 3100
        to     = 3100
      }

      dns {
        servers = ${dns}
      }
    }

    volume "loki-data" {
      type      = "host"
      read_only = false
      source    = "loki-data"
    }

    service {
      name     = "${servicename}"
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
      ]

      check {
        name     = "loki-ready"
        port     = "http"
        type     = "http"
        path     = "/ready"
        interval = "20s"
        timeout  = "5s"

        check_restart {
          limit           = 3
          grace           = "60s"
          ignore_warnings = false
        }
      }
    }

    task "loki" {
      user   = "10001:10001"
      driver = "podman"

      config {
        image  = "${image}"
        userns = "keep-id:uid=10001,gid=10001"
        args = [
          "-config.file",
          "local/local-config.yaml",
        ]
        ports = ["http"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
      }

      volume_mount {
        volume      = "loki-data"
        destination = "/loki"
        read_only   = false
      }

      template {
        data        = <<EOH
auth_enabled: false

server:
  http_listen_port: 3100

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 336h

compactor:
  retention_enabled: true
  delete_request_store: filesystem
  working_directory: /loki/compactor
EOH
        destination = "local/local-config.yaml"
        change_mode = "signal"
        change_signal = "SIGHUP"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
