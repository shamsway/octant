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
  url                   = "https://opapi.shamsway.net"
  token                 = "${var.OP_API_TOKEN}"
  op_cli_path           = "/usr/local/bin/op"
}

data "onepassword_vault" "dev" {
  name = "Dev"
}

data "onepassword_item" "job_pass" {
  vault = data.onepassword_vault.dev.uuid
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
  }
}

# Register job
resource "nomad_job" "job_name" {
  jobspec = "${data.template_file.job_template.rendered}"
}