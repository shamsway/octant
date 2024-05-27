# unset CLOUDFLARE_API_TOKEN && unset CLOUDFLARE_USERNAME && unset OP_API_TOKEN
# export CLOUDFLARE_EMAIL=mattadamelliott@gmail.com
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.33.0"
    }    
    onepassword = {
      source = "1Password/onepassword"
      version = "2.0.0"
    }
  }
}

# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

# Configure the Consul provider
provider "consul" {
  address = "http://${var.consul}:8500"
}

# Configure 1password provider
provider "onepassword" {
  account = "2KKYX7XVHNF47GJDK3HHVZEJX4"
  op_cli_path = "/usr/local/bin/op"
}

provider "cloudflare" {
  #api_token = "${var.cloudflare_token}"
}

data "onepassword_vault" "dev" {
  name = "Dev"
}

data "onepassword_item" "cloudflare_credentials" {
  vault = data.onepassword_vault.dev.uuid
  title = "Cloudflare_API_Key"
}

data "onepassword_item" "postgres_n8n_credentials" {
  vault = data.onepassword_vault.dev.uuid
  title = "postgres_n8n"
}

data "onepassword_item" "n8n_admin" {
  vault = data.onepassword_vault.dev.uuid
  title = "n8n.shamsway.net"
}

data "cloudflare_zone" "domain" {
    name = var.domain_name
}

resource "onepassword_item" "n8n_cloudflared" {
  vault = data.onepassword_vault.dev.uuid

  title    = "n8n_cloudflared"
  category = "password"

  password_recipe {
    length  = 32
    symbols = false
  }
}

resource "cloudflare_access_application" "n8n" {
  zone_id                   = data.cloudflare_zone.domain.zone_id
  name                      = "n8n"
  domain                    = "n8n.shamsway.net"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
}

resource "cloudflare_access_policy" "n8n_policy" {
  application_id    = cloudflare_access_application.n8n.id
  zone_id           = data.cloudflare_zone.domain.zone_id
  name              = "n8n policy"
  precedence        = "1"
  decision          = "bypass"
  include {
    everyone = true
  }  
}

resource "cloudflare_tunnel" "n8n_tunnel" {
  account_id = data.cloudflare_zone.domain.account_id
  name       = "n8n"
  secret     = base64encode(onepassword_item.n8n_cloudflared.password)
}

resource "cloudflare_tunnel_config" "n8n_tunnel_config" {
  account_id = data.cloudflare_zone.domain.account_id
  tunnel_id  = cloudflare_tunnel.n8n_tunnel.id
  config {
   ingress_rule {
     hostname = "n8n.shamsway.net"
     service  = "http://n8n.service.consul:5678"
   }
   ingress_rule {
     service  = "http_status:404"
   }
  }
}

resource "nomad_variable" "job_password" {
  path = "nomad/jobs/n8n"
  items = {
    n8n_postgres_user = data.onepassword_item.postgres_n8n_credentials.username
    n8n_postgres_password = data.onepassword_item.postgres_n8n_credentials.password
    n8n_admin_username = data.onepassword_item.n8n_admin.username
    n8n_admin_password = data.onepassword_item.n8n_admin.password
    #n8n_cloudflared = base64encode(onepassword_item.n8n_cloudflared.password)
    n8n_cloudflared = cloudflare_tunnel.n8n_tunnel.tunnel_token
  }
}

data "template_file" "job_template" {
  template = "${file("./n8n.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
    n8n_host = var.n8n_host
    n8n_public_url = var.n8n_public_url
    postgres_host = var.postgres_host
    postgres_db = var.postgres_db    
  }
}

# Register job
resource "nomad_job" "job_name" {
  jobspec = "${data.template_file.job_template.rendered}"
}