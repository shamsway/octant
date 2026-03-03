variable "nomad" {
  description = "Nomad server address"
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
  default = "docker.io/louislam/uptime-kuma:2.1.3"
}

variable "consul" {
  description = "Consul server address"
  type        = string
  default     = "localhost"
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
  default = "uptimekuma"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
}

variable "mariadb_host" {
  description = "MariaDB hostname"
  type        = string
  default     = "mariadb.service.consul"
}

variable "mariadb_db" {
  description = "MariaDB database name for Uptime Kuma"
  type        = string
  default     = "uptimekuma"
}
