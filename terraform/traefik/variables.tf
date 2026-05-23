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
  description = "Consul server address (must be routable from inside containers, not localhost)"
  type        = string
  default     = "192.168.122.101"
}

variable "region" {
  type = string
  default = "home"
}

variable "datacenter" {
  type = string
  default = "octant"
}

variable "traefik_image" {
  type = string
  default = "docker.io/traefik:v3.0.2"
}

variable "nginx_image" {
  type = string
  default = "docker.io/nginx"
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
  type = string
  default = "traefik"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}


variable "admin_email" {
  description = "Admin email for ACME certificate registration"
  type        = string
  default     = ""
}

