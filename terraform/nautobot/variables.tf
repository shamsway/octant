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
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
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
