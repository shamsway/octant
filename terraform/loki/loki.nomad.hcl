job "loki" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  constraint {
    attribute = "$${node.unique.name}"
    value     = "${node_name}"
  }

  group "loki" {
    count = 1

    volume "loki-data" {
      type            = "csi"
      source          = "loki-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      port "http" {
        static = 3100
        to     = 3100
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      port     = "http"
      provider = "consul"
      task     = "loki"

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
        "homepage.name=Loki",
        "homepage.icon=loki",
        "homepage.description=Log Aggregation",
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

    task "volume-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      volume_mount {
        volume      = "loki-data"
        destination = "/loki"
      }

      config {
        image   = "busybox:latest"
        command = "/bin/sh"
        args    = ["-c", "chown -R 10001:10001 /loki"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "loki" {
      driver = "docker"
      user   = "10001:10001"

      config {
        image = "${image}"
        args = [
          "-config.file",
          "local/local-config.yaml",
        ]
        ports = ["http"]

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
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
