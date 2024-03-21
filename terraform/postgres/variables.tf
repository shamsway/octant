variable "inventory_vars" {
  description = "Path to Ansible inventory varibles"
  type        = string
  default     = "~/Documents/git/homelab/inventory/group_vars/all.yml"
}

/* variable "inventory" {
  description = "Path to Ansible inventory"
  type        = string
  default     = "~/Documents/git/homelab/inventory/groups.yml"
} */

variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.shamsway.net"
}

variable "region" {
    type = string
    default = "home"
}

variable "shared_dir" {
    type = string
    default = "/opt/storage/"
}

variable "datacenter" {
    type = string
    default = "home"
}

variable "image" {
    type = string
    default = "docker.io/postgres:16.2"
}

variable "postgres_password" {
    type = string
    default = "P0$tgr3$4Lyf3"
}