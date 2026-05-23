job "neo4j" {
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

  group "neo4j" {
    count = 1

    volume "neo4j-data" {
      type            = "csi"
      source          = "neo4j-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

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
      task     = "neo4j"
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
      task     = "neo4j"
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
        "homepage.group=Databases",
        "homepage.name=Neo4j",
        "homepage.icon=neo4j",
        "homepage.description=Graph DB",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "volume-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      volume_mount {
        volume      = "neo4j-data"
        destination = "/data"
      }

      config {
        image   = "busybox:latest"
        command = "/bin/sh"
        args    = ["-c", "chown -R 7474:7474 /data"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "neo4j" {
      driver = "docker"

      volume_mount {
        volume      = "neo4j-data"
        destination = "/data"
      }

      config {
        image = "${image}"
        ports = ["http", "bolt"]

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
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
