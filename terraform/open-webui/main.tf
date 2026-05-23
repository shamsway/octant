terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
    }
  }
}

provider "nomad" {
  address = "http://${var.nomad}:4646"
}

provider "onepassword" {}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "litellm_credentials" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_litellm"
}

resource "nomad_variable" "open_webui_secrets" {
  path = "nomad/jobs/open-webui"
  items = {
    litellm_key = data.onepassword_item.litellm_credentials.password
  }
}

resource "nomad_job" "open_webui" {
  jobspec = templatefile("${path.module}/open-webui.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    ollama_url   = var.ollama_url
    webui_auth   = var.webui_auth
    webui_name   = var.webui_name
    webui_url    = var.webui_url
  })
  depends_on = [nomad_variable.open_webui_secrets]
}
