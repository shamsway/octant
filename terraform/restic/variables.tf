variable "OP_API_TOKEN" {
  description = "Auth token for 1password connect vault"
  type = string
}

variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.shamsway.net"
}

variable "image" {
    type = string
    default = "restic/restic:latest"
}

variable "restic_hostname" {
  description = "Restic hostname"
  type        = string
  default     = "octant-backup"
}

variable "restic_password" {
  description = "Restic backup password"
  type        = string
  sensitive   = true
}

variable "AWS_ACCESS_KEY_ID" {
  description = "Backblaze key ID for restic"
  type        = string
  sensitive   = true
}

variable "AWS_SECRET_ACCESS_KEY" {
  description = "Backblaze key for restic"
  type        = string
  sensitive   = true
}

variable "region" {
    type = string
    default = "home"
}

variable "datacenter" {
    type = string
    default = "shamsway"
}