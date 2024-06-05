terraform {
  required_providers {
    consul = {
      source = "hashicorp/consul"
      version = "2.20.0"
    }
  }
}

provider "consul" {
  address    = "${var.consul}:8500"
  datacenter = "shamsway"
}

resource "consul_config_entry" "mesh" {
    name      = "mesh"
    kind      = "mesh"

    config_json = jsonencode({
        AllowEnablingPermissiveMutualTLS = true
        TransparentProxy = {
          MeshDestinationsOnly = false
        }        
    })
}

resource "consul_config_entry" "proxy_defaults" {
  kind = "proxy-defaults"
  name = "global"
  depends_on = [ consul_config_entry.mesh ]
  config_json = jsonencode({
    Config = {
      protocol = "http"
      address = {
        socket_address = {
          address = "0.0.0.0"
          port_value = "19001"
        }
      }
      envoy_prometheus_bind_addr = "0.0.0.0:9102"
    }
    MutualTLSMode = "permissive"
    AccessLogs = {
      Type = "stdout"
      Enabled = true      
    }
    Expose = {}
    MeshGateway = {}
    TransparentProxy = {}
  })
}  