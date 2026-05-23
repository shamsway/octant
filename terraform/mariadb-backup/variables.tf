variable "nomad" {
  description = "Nomad server address"
  type    = string
  default = "localhost"
}

variable "consul" {
  description = "Consul server address"
  type    = string
  default = "localhost"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}

variable "domain" {
  type    = string
  default = "octant.local"
}

variable "certresolver" {
  type    = string
  default = ""
}
