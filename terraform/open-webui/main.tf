terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
      version = "~> 1.3.0"
    }
  }
}

# Configure the Consul provider
provider "consul" {
  address = "http://${var.consul}:8500"
}


# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
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

data "onepassword_item" "litellm_credentials" {
  vault = data.onepassword_vault.dev.uuid
  title = "litellm"
}

resource "nomad_variable" "open_webui_secrets" {
  path = "nomad/jobs/open-webui"
  items = {
    litellm_key = data.onepassword_item.litellm_credentials.password
  }
}

data "template_file" "open_webui_template" {
  template = "${file("./open-webui.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
    domain = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns = jsonencode(var.dns)
    ollama_url = var.ollama_url
    webui_auth = var.webui_auth
    webui_name = var.webui_name
    webui_url = var.webui_url
  }
}

# Register job
resource "nomad_job" "open-webui" {
  jobspec = "${data.template_file.open_webui_template.rendered}"
}