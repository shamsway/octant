job "n8n" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  constraint {
    attribute = "$${node.unique.name}"
    value = "bobby-agent"
  }

  # Temporary until lab is fully on physical hardware
  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "n8n" {
    network {
      port "http" {
        static = 5678
        to = 5678
      }
      dns {
        servers = ["192.168.252.1", "192.168.252.7", "192.168.252.8"]
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
      task = "n8n"
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
        image = "${image}"
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
        AUTH_TYPE = "basic"
        N8N_HOST = "${n8n_host}"
        N8N_EDITOR_BASE_URL = "${n8n_public_url}"
        N8N_BASIC_AUTH_ACTIVE = "true"
        N8N_PORT = "5678"
        DB_TYPE = "postgresdb"
        DB_POSTGRESDB_HOST = "${postgres_host}"
        DB_POSTGRESDB_DATABASE = "${postgres_db}"
        DB_POSTGRESDB_PORT = "5432"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/n8n" -}}
AUTH_USERNAME={{ .n8n_admin_user }}
AUTH_PASSWORD={{ .n8n_admin_password }}
DB_POSTGRESDB_USER={{ .n8n_postgres_user }}
DB_POSTGRESDB_PASSWORD={{ .n8n_postgres_password }}
{{- end -}}
EOT
      }      
    }

    task "ha_n8n" {
      driver = "podman"
      user = "nonroot"

      config {
        image = "docker.io/cloudflare/cloudflared:latest"
        args = ["tunnel", "--loglevel", "debug", "run"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "n8n_cloudflared"
            }
          ]
        }         
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/n8n" -}}
TUNNEL_TOKEN={{ .n8n_cloudflared }}
{{- end -}}
EOT
      }

      resources {
        memory = 128
      }      
    }
  }
}