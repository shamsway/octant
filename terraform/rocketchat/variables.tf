variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
}

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
  default = "docker.io/rocket.chat:latest"
}

variable "servicename" {
  type    = string
  default = "rocketchat"
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

variable "mongo_hosts" {
  description = "Comma-separated MongoDB replica set hosts"
  type        = string
  default     = "mongodb-1.service.consul:27017,mongodb-2.service.consul:27017,mongodb-3.service.consul:27017"
}

variable "mongo_db" {
  type    = string
  default = "rocketchat"
}
