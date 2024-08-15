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
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
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
  type    = string
  default = "mysecret"
}

variable "salt" {
  type    = string
  default = "mysalt"
}

variable "telemetry_enabled" {
  type    = string
  default = "true"
}

variable "langfuse_enable_experimental_features" {
  type    = strubg
  default = "false"
}
