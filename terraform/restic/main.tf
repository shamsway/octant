terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
      version = "~> 1.3.0"
    }
  }
}

provider "nomad" {
  address = "http://${var.nomad}:4646"
}

provider "onepassword" {
  url                   = "https://opapi.shamsway.net"
  token                 = "${var.OP_API_TOKEN}"
  op_cli_path           = "/usr/local/bin/op"
}

data "local_file" "inventory_vars" {
  filename = "../../inventory/group_vars/all.yml"
}

data "local_file" "inventory" {
  filename = "../../inventory/groups.yml"
}

data "onepassword_vault" "dev" {
  name = "Dev"
}

data "onepassword_item" "restic_pass" {
  vault = data.onepassword_vault.dev.uuid
  title = "Restic"
}

data "onepassword_item" "backblaze" {
  vault = data.onepassword_vault.dev.uuid
  title = "Backblaze"
}

locals {
  inventory         = yamldecode(data.local_file.inventory.content)
  inventory_vars    = yamldecode(data.local_file.inventory_vars.content)
  backup_volumes    = local.inventory.servers.vars.volumes
  #restic_password   = var.restic_password
  restic_repository = local.inventory_vars.restic_repository
}

data "template_file" "restic_job" {
  template = file("${path.module}/restic.nomad.hcl")

  vars = {
    region            = var.region
    datacenter        = local.inventory_vars.datacenter
    image             = var.image
    #backup_volumes    = jsonencode(local.backup_volumes)
    restic_repository = "${local.restic_repository}/nfs"
    restic_hostname   = var.restic_hostname
    # Filter the volumes to include only those with backup = true or backup attribute missing
    backup_volumes = jsonencode([
      for volume in local.backup_volumes :
      volume.path
      if lookup(volume, "backup", true)
    ])
  }    
}

resource "nomad_variable" "restic_password" {
  path = "nomad/jobs/restic-backup"
  items = {
    restic_password = data.onepassword_item.restic_pass.password
    AWS_ACCESS_KEY_ID = data.onepassword_item.backblaze.username
    AWS_SECRET_ACCESS_KEY = data.onepassword_item.backblaze.username
  }
}

resource "nomad_job" "restic_backup" {
  jobspec = data.template_file.restic_job.rendered
}