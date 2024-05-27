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
  default = "docker.io/n8nio/n8n:1.42.1"
}

variable "domain_name" {
  default = "shamsway.net"
}

variable "postgres_host" {
  default = "postgres.service.consul"
}

variable "postgres_db" {
  default = "n8n"
}

variable "n8n_host" {
  default = "n8n.service.consul"
}

variable "n8n_public_url" {
  default = "n8n.shamsway.net"
}