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

variable "csi_image" {
  description = "ceph-csi container image"
  type        = string
  default     = "quay.io/cephcsi/cephcsi:v3.12.2"
}

variable "ceph_fsid" {
  description = "Ceph cluster FSID (from 'ceph fsid')"
  type        = string
}

variable "ceph_monitors" {
  description = "Ceph monitor addresses"
  type        = list(string)
  default     = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}
