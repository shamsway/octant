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
  default = "docker.io/grafana/alloy:v1.8.3"
}

variable "servicename" {
  type    = string
  default = "alloy"
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

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
