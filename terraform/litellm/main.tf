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

data "onepassword_item" "litellm_credentials" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_litellm"
}

data "onepassword_item" "postgres_litellm" {
  vault = data.onepassword_vault.vault.uuid
  title = "db_litellm"
}

data "onepassword_item" "openai_key" {
  vault = data.onepassword_vault.vault.uuid
  title = "api_openai_key"
}

# Additional provider API keys (uncomment as needed):
# Requires corresponding 1Password items and Nomad variable entries.
# See config.yaml.example for the full model list.
#
# data "onepassword_item" "anthropic_key" {
#   vault = data.onepassword_vault.vault.uuid
#   title = "api_anthropic_key"
# }
#
# data "onepassword_item" "replicate_key" {
#   vault = data.onepassword_vault.vault.uuid
#   title = "api_replicate_key"
# }
#
# data "onepassword_item" "openrouter_key" {
#   vault = data.onepassword_vault.vault.uuid
#   title = "api_openrouter_key"
# }
#
# data "onepassword_item" "cohere_key" {
#   vault = data.onepassword_vault.vault.uuid
#   title = "api_cohere_key"
# }
#
# data "onepassword_item" "groq_key" {
#   vault = data.onepassword_vault.vault.uuid
#   title = "api_groq_key"
# }
#
# data "onepassword_item" "langfuse_key" {
#   vault = data.onepassword_vault.vault.uuid
#   title = "api_langfuse_key"
# }

data "local_file" "proxy_config" {
  filename = "config.yaml"
}

resource "nomad_variable" "litellm_secrets" {
  path = "nomad/jobs/litellm"
  items = {
    litellm_username   = data.onepassword_item.litellm_credentials.username
    litellm_password   = data.onepassword_item.litellm_credentials.password
    db_username        = data.onepassword_item.postgres_litellm.username
    db_password        = data.onepassword_item.postgres_litellm.password
    openai_key         = data.onepassword_item.openai_key.password
    proxy_config       = data.local_file.proxy_config.content
  }
}

data "template_file" "litellm_job_template" {
  template = "${file("./litellm.nomad.hcl")}"
  vars = {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    db_name      = var.db_name
    db_server    = var.db_server
  }
}

# Register job
resource "nomad_job" "litellm" {
  jobspec = "${data.template_file.litellm_job_template.rendered}"
}
