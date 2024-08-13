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

data "onepassword_item" "litellm_credentials" {
  vault = data.onepassword_vault.dev.uuid
  title = "litellm"
}

data "onepassword_item" "postgres_litellm" {
  vault = data.onepassword_vault.dev.uuid
  title = "postgres_litellm"
}

data "onepassword_item" "openai_key" {
  vault = data.onepassword_vault.dev.uuid
  title = "OpenAI API Key"
}

data "onepassword_item" "anthropic_key" {
  vault = data.onepassword_vault.dev.uuid
  title = "Anthropic API Key"
}

data "onepassword_item" "replicate_key" {
  vault = data.onepassword_vault.dev.uuid
  title = "Replicate API Key"
}

data "onepassword_item" "openrouter_key" {
  vault = data.onepassword_vault.dev.uuid
  title = "Openrouter API Key"
}

data "onepassword_item" "choere_key" {
  vault = data.onepassword_vault.dev.uuid
  title = "Cohere API Key"
}

data "onepassword_item" "groq_key" {
  vault = data.onepassword_vault.dev.uuid
  title = "Groq API Key"
}

data "onepassword_item" "langfuse_key" {
  vault = data.onepassword_vault.dev.uuid
  title = "Langfuse API Key"
}

data "local_file" "proxy_config" {
  filename = "config.yaml"
}

resource "nomad_variable" "litellm_secrets" {
  path = "nomad/jobs/litellm"
  items = {
    litellm_username = data.onepassword_item.litellm_credentials.username
    litellm_password = data.onepassword_item.litellm_credentials.password
    db_username = data.onepassword_item.postgres_litellm.username
    db_password = data.onepassword_item.postgres_litellm.password
    openai_key = data.onepassword_item.openai_key.password
    anthropic_key = data.onepassword_item.anthropic_key.password
    replicate_key = data.onepassword_item.replicate_key.password
    openrouter_key = data.onepassword_item.openrouter_key.password
    choere_key = data.onepassword_item.choere_key.password
    groq_key = data.onepassword_item.groq_key.password
    langfuse_public_key = data.onepassword_item.langfuse_key.username
    langfuse_secret_key = data.onepassword_item.langfuse_key.password
    proxy_config = data.local_file.proxy_config.content
  }
}

data "template_file" "litellm_job_template" {
  template = "${file("./litellm.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
    domain = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns = jsonencode(var.dns)    
    db_name = var.db_name
    db_server = var.db_server
    langfuse_url = var.langfuse_url
  }
}

# Register job
resource "nomad_job" "litellm" {
  jobspec = "${data.template_file.litellm_job_template.rendered}"
}