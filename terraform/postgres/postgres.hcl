  # terraform apply -auto-approve
  # terraform destroy -auto-approve

job "postgres" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  meta {
    version = "2"
  }

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  affinity {
    attribute = "$${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "db" {
    count = 1

    network {
      port "postgres" {
        static = 5432
      }

      port "pgadmin" {
        to = 80
      }

      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }            
    }

    volume "postgres-data" {
      type      = "host"
      read_only = false
      source    = "postgres-data"
    }

    volume "pgweb-config" {
      type      = "host"
      read_only = false
      source    = "pgweb-config"
    }

    service {
      name = "postgres"
      provider = "consul"
      task = "postgres"      
      port = "postgres"

      connect {
        native = true
      }

      tags = ["alloc=$${NOMAD_ALLOC_ID}"]

      check {
        type     = "tcp"
        port     = "postgres"
        interval = "30s"
        timeout  = "5s"
      }
    }

    service {
      name = "pgadmin"
      provider = "consul"
      task = "pgadmin"
      port = "pgadmin"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",          
        "traefik.http.routers.pgadmin.rule=Host(`pgadmin.shamsway.net`)",
        "traefik.http.routers.pgadmin.entrypoints=web,websecure",
        "traefik.http.routers.pgadmin.tls.certresolver=cloudflare",
        "traefik.http.routers.pgadmin.middlewares=redirect-web-to-websecure@internal",
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

    task "postgres" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["postgres"]
        userns = "keep-id:uid=70,gid=70"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "postgres"
            }
          ]
        } 
      }

      volume_mount {
        volume      = "postgres-data"
        destination = "/appdata/postgres"
        read_only   = false
      }

      env {
        POSTGRES_DB       = "postgres"
        POSTGRES_USER     = "postgres"
        PGDATA            = "/appdata/postgres"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/postgres" }}POSTGRES_PASSWORD={{ .postgres_password }}{{ end }}
EOT
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }

    task "pgadmin" {
      driver = "podman"
      user = "5050"

      config {
        image = "docker.io/dpage/pgadmin4:latest"
        userns = "keep-id:uid=5050,gid=101"
        ports = ["pgadmin"]
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