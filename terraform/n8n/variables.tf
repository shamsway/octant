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

variable "n8n_image" {
  type    = string
  default = "docker.io/n8nio/n8n:1.122.5"
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
  default = "n8n"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "postgres_host" {
  type    = string
  default = "postgres.service.consul"
}

variable "postgres_db" {
  type    = string
  default = "n8n"
}

variable "n8n_host" {
  type    = string
  default = "n8n.service.consul"
}

variable "n8n_public_url" {
  type    = string
  default = "http://n8n.octant.local"
}
