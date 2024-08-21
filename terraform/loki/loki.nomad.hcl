variable "datacenter" {
  type = string
  default = "octant"
}

variable "domain" {
  type = string
  default = "octant.net"
}

variable "certresolver" {
  type = string
  default = "cloudflare"
}

variable "servicename" {
  type = string
  default = "loki"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "image" {
  type = string
  default = "docker.io/grafana/loki:2.9.4"
}

job "loki" {
  region      = "home"
  datacenters = ["${var.datacenter}"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  group "monitoring" {
    network {
      port "loki" {
        static = 3100
      }
    }

    volume "loki-data" {
      type      = "host"
      read_only = false
      source    = "loki-data"
    }

    task "loki" {
      user = "10001:10001"
      driver = "podman"
      config {
        image = var.image
        userns = "keep-id:uid=10001,gid=10001"
        args = [
          "-config.file",
          "local/local-config.yaml",
        ]
        ports = ["loki"]
      }

      volume_mount {
        volume      = "loki-data"
        destination = "/loki"
        read_only   = false
      }

      service {
        name = "${var.servicename}"
        port = "loki"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${var.servicename}.rule=Host(`${var.servicename}.${var.domain}`)",
          "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
          "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
          "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",     
        ]    

        check {
          name     = "Loki healthcheck"
          port     = "loki"
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
      template {
        data = <<EOH
auth_enabled: false
server:
  http_listen_port: 3100
ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  # Any chunk not receiving new logs in this time will be flushed
  chunk_idle_period: 1h
  # All chunks will be flushed when they hit this age, default is 1h
  max_chunk_age: 1h
  # Loki will attempt to build chunks up to 1.5MB, flushing if chunk_idle_period or max_chunk_age is reached first
  chunk_target_size: 1048576
  # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
  chunk_retain_period: 30s
  max_transfer_retries: 0     # Chunk transfers disabled
  wal:
    dir: "/tmp/wal"
schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h         # Can be increased for faster performance over longer query periods, uses more disk space
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks
compactor:
  working_directory: /tmp/loki/boltdb-shipper-compactor
  shared_store: filesystem
limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
chunk_store_config:
  max_look_back_period: 0s
table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOH
        destination = "local/local-config.yaml"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}