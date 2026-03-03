variable "nomad" {
  description = "Nomad server address"
  type        = string
  default     = "localhost"
}

variable "consul" {
  description = "Consul server address"
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

variable "domain" {
  type    = string
  default = "octant.local"
}

variable "certresolver" {
  type    = string
  default = ""
}

variable "servicename" {
  type    = string
  default = "searxng"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "searxng_image" {
  type    = string
  default = "docker.io/searxng/searxng:latest"
}

variable "redis_image" {
  type    = string
  default = "docker.io/valkey/valkey:8-alpine"
}

variable "uwsgi_workers" {
  type    = string
  default = "4"
}

variable "uwsgi_threads" {
  type    = string
  default = "4"
}
