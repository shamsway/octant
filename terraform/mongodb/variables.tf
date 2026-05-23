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
  default = "docker.io/mongo:8.0"
}

variable "members" {
  description = "MongoDB replica set members: name -> node mapping"
  type        = map(object({ node = string }))
  default = {
    "mongodb-1" = { node = "octant-01-agent-root" }
    "mongodb-2" = { node = "octant-02-agent-root" }
    "mongodb-3" = { node = "octant-03-agent-root" }
  }
}

variable "mongo_hosts" {
  description = "Comma-separated host list for replica set connection strings"
  type        = string
  default     = "mongodb-1.service.consul:27017,mongodb-2.service.consul:27017,mongodb-3.service.consul:27017"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
