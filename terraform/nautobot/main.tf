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

data "onepassword_item" "nautobot_secrets" {
  vault = data.onepassword_vault.dev.uuid
  title = "Nautobot"
}

data "onepassword_item" "nautobot_db_credentials" {
  vault = data.onepassword_vault.dev.uuid
  title = "nautobot_db"
}

resource "nomad_variable" "nautobot_secrets" {
  path = "nomad/jobs/nautobot"
  items = {
    nautobot_username = data.onepassword_item.nautobot_secrets.username
    nautobot_password = data.onepassword_item.nautobot_secrets.password
    nautobot_api_key = one(flatten([
      for s in data.onepassword_item.nautobot_secrets.section : 
        [ for f in s.field : f.value if f.label == "api_key" ]
    ]))    
    nautobot_secret_key = one(flatten([
      for s in data.onepassword_item.nautobot_secrets.section : 
        [ for f in s.field : f.value if f.label == "secret_key" ]
    ]))
  }
}

data "local_file" "uwsgi_ini" {
  filename = "uwsgi.ini.example"
}

data "template_file" "nautobot_config" {
  template = "${file("./nautobot_config.py.tmpl")}"
  vars = {
    db_user = data.onepassword_item.nautobot_db_credentials.username
    db_password = data.onepassword_item.nautobot_db_credentials.password
    db_name = var.db_name
    db_host = var.db_host
    redis_host = var.redis_host
    admin_name = var.admin_name
    admin_email = var.admin_email
    secret_key = one(flatten([
      for s in data.onepassword_item.nautobot_secrets.section : 
        [ for f in s.field : f.value if f.label == "secret_key" ]
    ]))
  }
}

data "template_file" "nautobot_job" {
  template = "${file("./nautobot.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
    nautobot_config = base64encode(data.template_file.nautobot_config.rendered)
    uwsgi_ini = data.local_file.uwsgi_ini.content_base64
    nautobot_superuser_email = var.admin_email
    redis_host = var.redis_host
  }
}

# Register Nautobot job
resource "nomad_job" "nautobot" {
  jobspec = "${data.template_file.nautobot_job.rendered}"
}