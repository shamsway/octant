  # terraform apply -auto-approve
  # terraform destroy -auto-approve

job "postgres" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "postgres" {
    count = 1

    network {
      port "postgres" {
        static = 5432
      }


      dns {
        servers = ${dns}
      }            
    }

    volume "postgres-data" {
      type      = "host"
      read_only = false
      source    = "postgres-data"
    }

    service {
      name = "${servicename}"
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

    task "postgres" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["postgres"]
        userns = "keep-id:uid=70,gid=70"
        image_pull_timeout = "15m"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
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
  }
}