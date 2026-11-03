variable "name" {
  description = "Multipass VM name"
  type        = string
}

variable "image" {
  description = "Multipass image alias"
  type        = string
}

variable "cpus" {
  description = "vCPUs for this VM"
  type        = number
}

variable "memory" {
  description = "Memory for this VM, Multipass size format"
  type        = string
}

variable "disk" {
  description = "Disk for this VM, Multipass size format"
  type        = string
}

variable "cloud_init" {
  description = "Rendered cloud-init user-data passed to multipass launch"
  type        = string
}
