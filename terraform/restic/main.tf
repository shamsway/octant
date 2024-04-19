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
  inventory         = yamldecode(data.local_file.inventory.content)
  inventory_vars    = yamldecode(data.local_file.inventory_vars.content)
  backup_volumes    = local.inventory.servers.vars.volumes
  restic_password   = var.restic_password
  restic_repository = local.inventory_vars.restic_repository
}

data "template_file" "restic_job" {
  template = file("${path.module}/restic.hcl")

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
    restic_password = local.restic_password
    AWS_ACCESS_KEY_ID = var.AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = var.AWS_SECRET_ACCESS_KEY
  }
}

resource "nomad_job" "restic_backup" {
  jobspec = data.template_file.restic_job.rendered
}