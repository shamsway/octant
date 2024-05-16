job "nautobot" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  # Temporary until lab is fully on physical hardware
  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "nautobot" {
    network {
      port "http" {
        to = 8000 
      }

      port "https" {
        to = 8443 
      }

      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }      
    }

    volume "nautobot-config" {
      type      = "host"
      read_only = false
      source    = "nautobot-config"
    }

    service {
      name = "nautobot"
      task = "nautobot"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.nautobot.rule=Host(`nautobot.shamsway.net`)",
        "traefik.http.routers.nautobot.entrypoints=web,websecure",
        "traefik.http.routers.nautobot.tls.certresolver=cloudflare",
        "traefik.http.routers.nautobot.middlewares=redirect-web-to-websecure@internal",
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

    task "nautobot" {
      driver = "podman"
      user = "nautobot"

      config {
        image = "docker.io/networktocode/nautobot"
        ports = ["http","https"]
        volumes = ["local/uwsgi.ini:/opt/nautobot/uwsgi.ini","secrets/nautobot_config.py:/opt/nautobot/nautobot_config.py"]
        userns = "keep-id:uid=999,gid=999"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "nautobot"
            }
          ]
        }         
      }

      volume_mount {
        volume      = "nautobot-config"
        destination = "/opt/nautobot/"
        read_only   = false
      }

      env {
        NAUTOBOT_CREATE_SUPERUSER=true
        NAUTOBOT_SUPERUSER_EMAIL="${nautobot_superuser_email}"
        NAUTOBOT_REDIS_HOST="${redis_host}"
        NAUTOBOT_REDIS_PORT=6379
        NAUTOBOT_CACHEOPS_REDIS="redis://${redis_host}:6379/1"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/nautobot" -}}
NAUTOBOT_SUPERUSER_NAME={{ .nautobot_username }}
NAUTOBOT_SUPERUSER_PASSWORD={{ .nautobot_password }}
NAUTOBOT_SUPERUSER_API_TOKEN={{ .nautobot_api_key }}
{{- end -}}
EOT
      }

      template {
        destination = "$${NOMAD_TASK_DIR}/uwsgi.ini"
        data = base64decode("${uwsgi_ini}")
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/nautobot_config.py"
        data = base64decode("${nautobot_config}")
      }

      resources {
        memory = 384
      }
    }
  }
}