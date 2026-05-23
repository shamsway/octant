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

variable "consul" {
  description = "Consul server address"
  type        = string
  default     = "localhost"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}

variable "image" {
  type    = string
  default = "docker.io/dpage/pgadmin4:latest"
}

variable "domain" {
  type    = string
  default = "octant.local"
}

variable "certresolver" {
  type    = string
  default = ""
}

variable "servicename" {
  type    = string
  default = "pgadmin"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "pgadmin_email" {
  type    = string
  default = "pgadmin@octant.net"
}
