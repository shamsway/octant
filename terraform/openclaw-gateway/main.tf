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

data "onepassword_item" "service_openclaw" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_openclaw"
}

data "onepassword_item" "bot_openclaw_rocketchat" {
  vault = data.onepassword_vault.vault.uuid
  title = "bot_openclaw_rocketchat"
}

data "onepassword_item" "api_anthropic_key" {
  vault = data.onepassword_vault.vault.uuid
  title = "api_anthropic_key"
}

data "onepassword_item" "service_litellm" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_litellm"
}

resource "nomad_variable" "openclaw_gateway_secrets" {
  path = "nomad/jobs/openclaw-gateway"
  items = {
    openclaw_gateway_token = data.onepassword_item.service_openclaw.password
    rocketchat_bot_user     = data.onepassword_item.bot_openclaw_rocketchat.username
    rocketchat_bot_password = data.onepassword_item.bot_openclaw_rocketchat.password
    anthropic_api_key      = data.onepassword_item.api_anthropic_key.password
    litellm_api_key        = data.onepassword_item.service_litellm.password
  }
}

resource "nomad_job" "openclaw_gateway" {
  jobspec = templatefile("${path.module}/openclaw-gateway.nomad.hcl", {
    region           = var.region
    datacenter       = var.datacenter
    image            = var.image
    domain           = var.domain
    certresolver     = var.certresolver
    servicename      = var.servicename
    dns              = jsonencode(var.dns)
    litellm_base_url = var.litellm_base_url
  })
  depends_on = [nomad_variable.openclaw_gateway_secrets]
}
