variable "inventory_vars" {
  description = "Path to Ansible inventory varibles"
  type        = string
  default     = "../../inventory/group_vars/all.yml"
}

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

variable "datacenter" {
  type = string
  default = "shamsway"
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
  default = "home"
}

variable "image" {
  type = string
  default = "docker.io/postgres:16.2"
}

variable "pgadmin_email" {
  type = string
  default = "pgadmin@shamsway.net"
}