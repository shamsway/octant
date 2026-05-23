terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
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

# Configure 1password provider
provider "onepassword" {
  # Authenticates via OP_SERVICE_ACCOUNT_TOKEN environment variable
}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "job_pass" {
  vault = data.onepassword_vault.vault.uuid
  title = "[replace]"
}

resource "nomad_variable" "job_password" {
  path = "nomad/jobs/[job name]"
  items = {
    postgres_password = data.onepassword_item.job_pass.password
  }
}

data "template_file" "job_template" {
  template = "${file("./template.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
    domain = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns = jsonencode(var.dns)
  }
}

# Register job
resource "nomad_job" "job_name" {
  jobspec = "${data.template_file.job_template.rendered}"
}
