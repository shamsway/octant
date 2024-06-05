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
  default = "ghcr.io/berriai/litellm-database:main-stable"
}

variable "db_server" {
  type = string
  default = "postgres.service.consul"
}

variable "db_name" {
  type = string
  default = "litellm"
}

variable "langfuse_url" {
  type = string
  default = "https://langfuse.shamsway.net"
}