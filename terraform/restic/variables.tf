variable "OP_API_TOKEN" {
  description = "Auth token for 1password connect vault"
  type = string
}

variable "op_api_url" {
  description = "URL for 1password connect vault"
  type = string
  default = "https://opapi.octant.net"
}

variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.octant.net"
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
  description = "S3/Backblaze key ID for restic"
  type        = string
  sensitive   = true
}

variable "AWS_SECRET_ACCESS_KEY" {
  description = "S3/Backblaze key for restic"
  type        = string
  sensitive   = true
}

variable "region" {
    type = string
    default = "home"
}

variable "datacenter" {
    type = string
    default = "octant"
}