variable "consul" {
  description = "Consul server address"
  type = string
  default = "consul.octant.net"
}

variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.octant.net"
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
  default = "docker.io/plantuml/plantuml-server:v1.2024.5"
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
  default = "plantuml"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}