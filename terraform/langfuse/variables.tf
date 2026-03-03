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
  default = "ghcr.io/langfuse/langfuse:latest"
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
  default = "langfuse"
}

variable "dns" {
  type = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "db_server" {
  type = string
  default = "postgres.service.consul"
}

variable "db_name" {
  type = string
  default = "langfuse"
}

variable "nextauth_url" {
  type    = string
  default = "https://langfuse.octant.net"
}

variable "nextauth_secret" {
  description = "NextAuth secret - override with a secure random value"
  type        = string
  default     = "changeme"
}

variable "salt" {
  description = "Encryption salt - override with a secure random value"
  type        = string
  default     = "changeme"
}

variable "telemetry_enabled" {
  type    = string
  default = "true"
}

variable "langfuse_enable_experimental_features" {
  type    = strubg
  default = "false"
}
