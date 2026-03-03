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

data "onepassword_item" "restic_pass" {
  vault = data.onepassword_vault.vault.uuid
  title = "backup_restic_password"
}

data "local_file" "inventory_vars" {
  filename = "../../inventory/group_vars/all.yml"
}

data "local_file" "inventory" {
  filename = "../../inventory/groups.yml"
}

locals {
  inventory         = yamldecode(data.local_file.inventory.content)
  inventory_vars    = yamldecode(data.local_file.inventory_vars.content)
  backup_volumes    = local.inventory.servers.vars.volumes
  restic_repository = local.inventory_vars.restic_repository

  backup_paths = [
    for volume in local.backup_volumes :
    volume.path
    if lookup(volume, "backup", true)
  ]
}

resource "nomad_variable" "restic_backup" {
  path = "nomad/jobs/restic-backup"
  items = {
    backup_script         = templatefile("${path.module}/backup.sh.tmpl", {
      backup_volumes = jsonencode(local.backup_paths)
    })
    restic_password       = data.onepassword_item.restic_pass.password
    AWS_ACCESS_KEY_ID     = "unused"
    AWS_SECRET_ACCESS_KEY = "unused"
  }
}

resource "nomad_job" "restic_backup" {
  jobspec = templatefile("${path.module}/restic.nomad.hcl", {
    region            = var.region
    datacenter        = local.inventory_vars.datacenter
    image             = var.image
    restic_repository = local.restic_repository
    restic_hostname   = var.restic_hostname
    backup_volumes    = jsonencode(local.backup_paths)
  })
}
