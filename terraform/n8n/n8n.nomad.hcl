job "n8n" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  group "n8n" {
    network {
      port "http" {
        static = 5678
      }
      dns {
        servers = ["192.168.252.1", "192.168.252.7"]
      }      
    }

    volume "n8n-config" {
      type      = "host"
      read_only = false
      source    = "n8n-config"
    }

    service {
      name = "n8n"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.n8n.rule=Host(`n8n.shamsway.net`)",
        "traefik.http.routers.n8n.entrypoints=web,websecure",
        "traefik.http.routers.n8n.tls.certresolver=cloudflare",
        "traefik.http.routers.n8n.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "n8n" {
      driver = "podman"
      user = "1000"

      config {
        image = "docker.io/n8nio/n8n:1.40.0"
        ports = ["http"]
        userns = "keep-id:uid=1000,gid=1000"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "n8n"
            }
          ]
        }         
      }

      volume_mount {
        volume      = "n8n-config"
        destination = "/home/node/.n8n"
        read_only   = false
      }

      env {
        N8N_BASIC_AUTH_ACTIVE = "false"
        N8N_PORT = "5678"
        DB_TYPE = "postgresdb"
        DB_POSTGRESDB_HOST = "192.168.252.6"
        DB_POSTGRESDB_PORT = "5432"
        DB_POSTGRESDB_DATABASE = "n8n"
        DB_POSTGRESDB_USER = "postgres_n8n"
        DB_POSTGRESDB_PASSWORD = "6M!uf4EDFWu7UuMY"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}