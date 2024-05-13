  # terraform apply -auto-approve
  # terraform destroy -auto-approve

job "samba" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  meta {
    version = "1"
  }

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "samba" {
    count = 1

    network {
      port "smb" {
        static = 445
        to = 445
      }

      dns {
        servers = ["192.168.252.1","192.168.252.7"]
      }            
    }

    volume "media-library" {
      type      = "host"
      read_only = false
      source    = "media-library"
    }

    service {
      name = "samba"
      provider = "consul"
      task = "samba"      
      port = "smb"

      connect {
        native = true
      }

      check {
        type     = "tcp"
        port     = "smb"    
        interval = "30s"
        timeout  = "5s"
      }
    } 

    task "samba" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["smb"]
        #userns = "keep-id:uid=70,gid=70"
        #volumes = ["$${NOMAD_SECRETS_DIR}/config.json:/etc/samba-container/config.json"]
        volumes = ["secrets/config.json:/etc/samba-container/config.json"]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "samba"
            }
          ]
        } 
      }

      volume_mount {
        volume      = "media-library"
        destination = "/share/library"
        read_only   = false
      }

      env {
        #SAMBACC_CONFIG = "$${NOMAD_TASK_DIR}/sambacc_config.json"
        SAMBACC_CONFIG = "/etc/samba-container/config.json"
        SAMBA_CONTAINER_ID = "octantsmb"
      }

      template {
        destination   = "$${NOMAD_SECRETS_DIR}/config.json"
        data        = <<EOT
{
  "samba-container-config": "v0",
  "configs": {
    "octantsmb": {
      "instance_name": "OCTANTSMB",
      "instance_features": [],
      "shares": [
        "library"
      ],
      "globals": [
        "default"
      ]
    }
  },
  "shares": {
    "library": {
      "options": {
        "path": "/share/library",
        "valid users": "smbuser",
        "read only": "no"
      }
    }
  },
  "globals": {
    "default": {
      "options": {
        "security": "user",
        "server min protocol": "SMB2",
        "load printers": "no",
        "printing": "bsd",
        "printcap name": "/dev/null",
        "disable spoolss": "yes",
        "guest ok": "no"
      }
    }
  },
  "users": {
    "all_entries": [
      {
        "name": "smbuser",
        "password": "{{ with nomadVar "nomad/jobs/samba" }}{{ .smbuser_password }}{{ end }}"
      }
    ]
  },
   "_footer": 1
}
EOT

      }

      resources {
        cpu    = 100
        memory = 256
      }
    }    
  }
}