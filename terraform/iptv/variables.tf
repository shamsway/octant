variable "OP_API_TOKEN" {
  description = "Auth token for 1password connect vault"
  type = string
}

variable "OP_API_URL" {
  description = "URL for 1password connect vault"
  type = string
  default = "https://opapi.shamsway.net"
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

variable "tvh_image" {
  type = string
  default = "docker.io/linuxserver/tvheadend:b774bdd2-ls222"
}

variable "gluetun_image" {
  type = string
  default = "docker.io/qmcgaw/gluetun:latest"
}