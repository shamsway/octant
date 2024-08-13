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
  default = "shamsway"
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
  type = string
  default = "octant.net"
}

variable "certresolver" {
  type = string
  default = "cloudflare"
}

variable "servicename" {
  type = string
  default = "traefik"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}


variable "CLOUDFLARE_USERNAME" {
  type = string
}

variable "CLOUDFLARE_API_KEY" {
  type = string
  sensitive = true
}