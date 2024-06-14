variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.shamsway.net"
}

variable "region" {
  type = string
  default = "home"
}

variable "datacenter" {
  type = string
  default = "shamsway"
}

variable "image" {
  type = string
  default = "docker.io/plantuml/plantuml-server:v1.2024.5"
}