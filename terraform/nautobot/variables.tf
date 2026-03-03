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
  default = "docker.io/networktocode/nautobot:1.6.22-py3.10"
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
  default = "nautobot"
}

variable "dns" {
  type = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "admin_name" {
  type = string
  default = "Octant Admin"
}

variable "admin_email" {
  type = string
  default = "admin@octant.net"
}

variable "db_name" {
  type = string
  default = "nautobot"
}

variable "db_host" {
  type = string
  default = "postgres.service.consul"
}

variable "redis_host" {
  type = string
  default = "redis.service.consul"
}
