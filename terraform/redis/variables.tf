variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.shamsway.net"
}

variable "region" {
  type = string
  default = "home"
}

variable "datacenter" {
  type = string
  default = "shamsway"
}

variable "image" {
  type = string
  default = "docker.io/redis:7.2.4"
}