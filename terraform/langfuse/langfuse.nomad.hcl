job "langfuse" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }
  
  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "langfuse" {
    network {
      port "http" {
        to = 3000
      }

      dns {
        servers = ["192.168.252.1", "192.168.252.6", "192.168.252.7"]
      }         
    }

    service {
      name = "langfuse"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
		"traefik.consulcatalog.connect=false",
        "traefik.http.routers.langfuse.rule=Host(`langfuse.shamsway.net`)",
        "traefik.http.routers.langfuse.entrypoints=web,websecure",
        "traefik.http.routers.langfuse.tls.certresolver=cloudflare",
      ]

      connect {
        native = true
      }        

      check {
        name     = "alive"
        type     = "http"
        path     = "/api/public/health"
        interval = "60s"
        timeout  = "5s"
      }
    }       
    
    task "langfuse" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["http"]
        image_pull_timeout = "15m"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "open-webui"
            }
          ]
        }                 
      }

      env {
        NEXTAUTH_URL = "https://langfuse.shamsway.net"
        NEXTAUTH_SECRET = "mysecret"
        SALT = "mysalt"
        TELEMETRY_ENABLED = "true"
        LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES = "false"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/langfuse" -}}
DATABASE_URL="postgresql://{{ .db_username }}:{{ .db_password }}@${db_server}:5432/${db_name}"
{{- end -}}
EOT
      }    

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}