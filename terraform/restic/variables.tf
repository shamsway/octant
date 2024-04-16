variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.shamsway.net"
}

variable "image" {
    type = string
    default = "restic/restic:latest"
}

variable "restic_password" {
  description = "Restic backup password"
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