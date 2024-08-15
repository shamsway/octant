variable "OP_API_TOKEN" {
  description = "Auth token for 1password connect vault"
  type = string
}

variable "op_api_url" {
  description = "URL for 1password connect vault"
  type = string
  default = "https://opapi.octant.net"
}

variable "op_vault" {
  description = "Name of the 1password vault containing secrets"
  type = string
  default = "octant"
}

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

variable "datacenter" {
  type = string
  default = "octant"
}

variable "image" {
  type = string
  default = "[image name]"
}

variable "domain" {
  type = string
  default = "octant.net"
}

variable "certresolver" {
  type = string
  default = "cloudflare"
}

variable "servicename" {
  type = string
  default = "CHANGEMEEEEE"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}
