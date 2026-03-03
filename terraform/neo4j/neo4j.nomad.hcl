job "neo4j" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "neo4j" {
    count = 1

    network {
      port "http" {
        to = 7474
      }

      port "bolt" {
        to = 7687
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "bolt"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=false",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }

    service {
      name     = "${servicename}-ui"
      provider = "consul"
      port     = "http"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}-ui.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}-ui.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}-ui.tls.certresolver=${certresolver}",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "neo4j" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["http", "bolt"]

        volumes = [
          "/mnt/services/neo4j/data:/data",
          "/mnt/services/neo4j/logs:/logs"
        ]

        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
      }

      env {
        TZ = "America/New_York"

        # APOC procedures for advanced graph operations
        NEO4J_PLUGINS = "[\"apoc\"]"

        # JVM memory tuning
        NEO4J_server_memory_heap_initial__size = "512m"
        NEO4J_server_memory_heap_max__size     = "512m"
        NEO4J_server_memory_pagecache_size     = "256m"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/neo4j" -}}
NEO4J_AUTH=neo4j/{{ .NEO4J_PASSWORD }}
{{- end -}}
EOT
      }

      resources {
        cpu    = 1000
        memory = 1280
      }
    }
  }
}
