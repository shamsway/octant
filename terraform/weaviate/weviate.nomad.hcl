job "weaviate" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value      = true
  }

  affinity {
    attribute = "${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "weaviate" {
    network {
      port "http" {
        static = 50050
        to = 8080
      }

      port "grpc" {
        static = 50051
        to = 50051
      }

      port "metrics" {
        to = 2112
      }

      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
      }
    }

    service {
      name = "weaviate"
      provider = "consul"
      port = "http"
      tags   = [
        "traefik.enable=true",
        "traefik.https=true",
        "traefik.https.entrypoints=https", 
        "traefik.https.tls.certresolver=cloudflare",
        "traefik.http.routers.weaviate.rule=Host(`weaviate.shamsway.net`)",
      ]

      connect {
        native = true
      }

      check {
        name      = "alive"
        type      = "http"
        path      = "/v1/.well-known/ready"
        interval  = "10s"
        timeout   = "2s"
      }      
    }

    task "weaviate" {
      driver  = "podman"

      config {
        image = "cr.weaviate.io/semitechnologies/weaviate:1.25.3"
        volumes = ["/mnt/services/weviate/data:/var/lib/weaviate"]
        ports = ["http","grpc","metrics"]
        logging = {
        driver = "journald"
        options = [
            {
            "tag" = "weaviate"
            }
          ]
        } 
      }

      env {
        PROMETHEUS_MONITORING_ENABLED = "true"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}