variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.octant.net"
}

variable "consul" {
  description = "Consul server address"
  type = string
  default = "consul.octant.net"
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
  default = "octant"
}