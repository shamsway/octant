job "qdrant" {
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

  group "qdrant" {
    count = 1

    volume "qdrant-data" {
      type            = "csi"
      source          = "qdrant-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      port "http" {
        static = 6333
        to     = 6333
      }

      port "grpc" {
        static = 6334
        to     = 6334
      }

      port "internal" {
        static = 6335
        to     = 6335
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      task     = "qdrant"
      port     = "http"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "homepage.group=Databases",
        "homepage.name=Qdrant",
        "homepage.icon=qdrant",
        "homepage.description=Vector DB",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/healthz"
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
        volume      = "qdrant-data"
        destination = "/qdrant/storage"
      }

      config {
        image   = "busybox:latest"
        command = "/bin/sh"
        args    = ["-c", "chown -R 1000:1000 /qdrant/storage"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "qdrant" {
      driver = "docker"
      user   = "1000:1000"

      volume_mount {
        volume      = "qdrant-data"
        destination = "/qdrant/storage"
      }

      config {
        image = "${image}"
        ports = ["http", "grpc", "internal"]

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
        }
      }

      env {
        QDRANT__LOG_LEVEL = "INFO"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
