terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
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

# Configure 1password provider (SaaS via op CLI)
provider "onepassword" {
  # Authenticates via OP_SERVICE_ACCOUNT_TOKEN environment variable
}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "cloudflare_dns" {
  vault = data.onepassword_vault.vault.uuid
  title = "api_cloudflare_key"
}

data "template_file" "traefik_toml" {
  template = "${file("./traefik.toml")}"
  vars = {
    domain        = var.domain
    consul        = var.consul
    datacenter    = var.datacenter
    certresolver  = var.certresolver
    admin_email   = var.admin_email
  }
}

resource "nomad_variable" "cloudflare_secrets" {
  path = "nomad/jobs/traefik"
  items = {
    cloudflare_username = data.onepassword_item.cloudflare_dns.username
    cloudflare_api_key  = data.onepassword_item.cloudflare_dns.credential
    traefik_toml        = data.template_file.traefik_toml.rendered
  }
}

data "template_file" "traefik_job_template" {
  template = "${file("./traefik.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.traefik_image
    domain = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns = jsonencode(var.dns)
  }
}

# Register jobs
resource "nomad_job" "traefik" {
  depends_on = [nomad_variable.cloudflare_secrets]
  jobspec = "${data.template_file.traefik_job_template.rendered}"
}
