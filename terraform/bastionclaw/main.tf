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

data "onepassword_item" "api_anthropic_key" {
  vault = data.onepassword_vault.vault.uuid
  title = "api_anthropic_key"
}

data "onepassword_item" "service_litellm" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_litellm"
}

resource "nomad_variable" "bastionclaw_secrets" {
  path = "nomad/jobs/bastionclaw"
  items = {
    anthropic_api_key = data.onepassword_item.api_anthropic_key.password
    litellm_api_key   = data.onepassword_item.service_litellm.password
  }
}

resource "nomad_job" "bastionclaw" {
  jobspec = templatefile("${path.module}/bastionclaw.nomad.hcl", {
    region             = var.region
    datacenter         = var.datacenter
    image              = var.image
    agent_image        = var.agent_image
    domain             = var.domain
    certresolver       = var.certresolver
    servicename        = var.servicename
    dns                = jsonencode(var.dns)
    litellm_base_url   = var.litellm_base_url
    podman_socket_path = var.podman_socket_path
  })
  depends_on = [nomad_variable.bastionclaw_secrets]
}
