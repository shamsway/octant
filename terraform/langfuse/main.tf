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

data "onepassword_vault" "dev" {
  name = "Dev"
}

data "onepassword_item" "postgres_langfuse" {
  vault = data.onepassword_vault.dev.uuid
  title = "postgres_langfuse"
}


resource "nomad_variable" "job_password" {
  path = "nomad/jobs/langfuse"
  items = {
    db_username = data.onepassword_item.postgres_langfuse.username
    db_password = data.onepassword_item.postgres_langfuse.password
  }
}

data "template_file" "langfuse_template" {
  template = "${file("./langfuse.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
    db_name = var.db_name
    db_server = var.db_server
    domain = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns = jsonencode(var.dns)  
    nextauth_url = var.nextauth_url
    nextauth_secret = var.nextauth_secret
    salt = var.salt
    telemetry_enabled = var.telemetry_enabled
    langfuse_enable_experimental_features = var.langfuse_enable_experimental_features
  }
}

# Register job
resource "nomad_job" "langfuse" {
  jobspec = "${data.template_file.langfuse_template.rendered}"
}