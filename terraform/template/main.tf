terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
      version = "~> 1.3.0"
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
  url                   = "${var.op_api_url}"
  token                 = "${var.OP_API_TOKEN}"
  op_cli_path           = "/usr/local/bin/op"
}

data "onepassword_vault" "vault" {
  name = "${var.op_vault}"
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