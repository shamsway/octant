  # terraform apply -auto-approve
  # terraform destroy -auto-approve

job "postgres" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "pgadmin" {
    count = 1

    network {
      port "pgadmin" {
        to = 80
      }

      dns {
        servers = ${dns}
      }            
    }

    volume "pgweb-config" {
      type      = "host"
      read_only = false
      source    = "pgweb-config"
    }

    service {
      name = "${servicename}"
      provider = "consul"
      task = "pgadmin"
      port = "pgadmin"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    } 
    
    task "pgadmin" {
      driver = "podman"
      user = "5050"

      config {
        image = "docker.io/dpage/pgadmin4:latest"
        userns = "keep-id:uid=5050,gid=101"
        ports = ["pgadmin"]
        image_pull_timeout = "15m"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "pgadmin"
            }
          ]
        }         
      }  

      env {
        PGADMIN_DEFAULT_EMAIL     = "pgadmin@shamsway.net"
        PGADMIN_LISTEN_ADDRESS    = "0.0.0.0"
        PGDATA                    = "/appdata/postgres"
      }

      volume_mount {
        volume      = "pgweb-config"
        destination = "/var/lib/pgadmin"
        read_only   = false
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/postgres" }}PGADMIN_DEFAULT_PASSWORD={{ .postgres_password }}{{ end }}
EOT
      }    
      
      resources {
        memory = 128
      }        
    }      
  }
}