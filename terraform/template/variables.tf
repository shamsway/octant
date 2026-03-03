variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
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
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
