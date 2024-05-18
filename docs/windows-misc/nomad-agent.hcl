name = "joan-agent"
data_dir = "H:\hashi\nomad\data\nomad-agent"
datacenter = "shamsway"
region = "home"
bind_addr = "0.0.0.0"
log_level = "info"

server {
  enabled = false
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}

tls {
  ca_file   = "H:\hashi\consul\tls\consul-agent-ca.pem"
  cert_file = "H:\hashi\nomad\tls\home-client-nomad.pem"
  key_file  = "H:\hashi\nomad\tls\home-client-nomad-key.pem"
  rpc  = true
}

consul {
    auto_advertise = true
    server_auto_join = true
    client_auto_join = true
    address = "127.0.0.1:9501"
    grpc_address = "127.0.0.1:9503"
    ssl = true
    verify_ssl = true
    ca_file = "H:\hashi\consul\tls\consul-agent-ca.pem"
    cert_file = "H:\hashi\consul\tls\shamsway-client-consul-0.pem"
    key_file = "H:\hashi\consul\tls\shamsway-client-consul-0-key.pem"
    grpc_ca_file = "H:\hashi\consul\tls\consul-agent-ca.pem"
}

telemetry {
  publish_allocation_metrics = true
  publish_node_metrics       = true
  prometheus_metrics         = true
}

plugin "docker" {
  config {
    gc {
      image       = true
      image_delay = "3m"
      container   = true

      dangling_containers {
        enabled        = true
        dry_run        = false
        period         = "5m"
        creation_grace = "5m"
      }
    }

    volumes {
      enabled      = true
      selinuxlabel = "z"
    }
  }
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

client {
  enabled = true

  meta {
    rootless = true
  }

  host_volume "tvheadend-recordings" {
      path      = "H:\recordings\tvheadend"
      read_only = false
  }

  host_volume "llm-models" {
      path      = "G:\llm-models"
      read_only = false
  }
}