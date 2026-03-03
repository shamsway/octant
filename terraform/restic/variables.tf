variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
}

variable "nomad" {
  description = "Nomad server address"
  type        = string
  default     = "localhost"
}

variable "image" {
  type    = string
  default = "restic/restic:latest"
}

variable "restic_hostname" {
  description = "Restic hostname"
  type        = string
  default     = "octant-backup"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}
