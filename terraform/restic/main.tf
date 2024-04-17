# Initialize before running

# podman run --rm --hostname restic-host -ti \
#     -e RESTIC_REPOSITORY=your_repository_url \
#     -e RESTIC_PASSWORD=your_restic_password \
#     restic/restic init
#
# Add AWS stuff

provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "local_file" "inventory_vars" {
  filename = "../../inventory/group_vars/all.yml"
}

data "local_file" "inventory" {
  filename = "../../inventory/groups.yml"
}

locals {
  inventory          = yamldecode(data.local_file.inventory.content)
  inventory_vars     = yamldecode(data.local_file.inventory_vars.content)
  backup_volumes     = local.inventory.servers.vars.volumes
  restic_password    = var.restic_password
  restic_repository  = local.inventory_vars.restic_repository
}

data "template_file" "restic_job" {
  template = file("${path.module}/restic.hcl")

  vars = {
    region            = var.region
    datacenter        = local.inventory_vars.datacenter
    image             = var.image
    backup_volumes    = jsonencode(local.backup_volumes)
    restic_password   = local.restic_password
    restic_repository = local.restic_repository
    restic_hostname   = var.restic_hostname
  }
}

resource "nomad_job" "restic_backup" {
  jobspec = data.template_file.restic_job.rendered
}