variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
}

variable "inventory_vars" {
  description = "Path to Ansible inventory varibles"
  type        = string
  default     = "../../inventory/group_vars/all.yml"
}

variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "localhost"
}

variable "consul" {
  description = "Consul server address"
  type = string
  default = "localhost"
}

variable "datacenter" {
  type = string
  default = "octant"
}

variable "region" {
  type = string
  default = "home"
}

variable "shared_dir" {
  type = string
  default = "/opt/storage/"
}

variable "image" {
  type = string
  default = "docker.io/postgres:16.2"
}

variable "pgadmin_email" {
  type = string
  default = "pgadmin@octant.net"
}
