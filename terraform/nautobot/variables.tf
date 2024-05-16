variable "OP_API_TOKEN" {
  description = "Auth token for 1password connect vault"
  type = string
}

variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.shamsway.net"
}

variable "consul" {
  description = "Consul server address"
  type = string
  default = "consul.shamsway.net"
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
  default = "docker.io/networktocode/nautobot:1.6.22-py3.10"
}

variable "admin_name" {
  type = string
  default = "Octant Admin"
}

variable "admin_email" {
  type = string
  default = "admin@shamsway.net"
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
