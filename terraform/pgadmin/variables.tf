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

variable "shared_dir" {
  type = string
  default = "/opt/storage/"
}

variable "datacenter" {
  type = string
  default = "octant"
}

variable "image" {
  type = string
  default = "docker.io/dpage/pgadmin4:latest"
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
  default = "pgadmin"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "pgadmin_email" {
  type = string
  default = "pgadmin@octant.net"
}