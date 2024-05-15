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
  default = "docker.io/linuxserver/tvheadend:b1005850-ls211"
}

variable "gluetun_image" {
  type = string
  default = "docker.io/qmcgaw/gluetun:latest"
}