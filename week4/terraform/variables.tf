variable "name_prefix" {
  description = "Prefix for every VM name"
  type        = string
  default     = "kijanikiosk"
}

variable "ssh_public_key_path" {
  description = "Public key injected into each VM via cloud-init; Ansible uses the matching private key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ubuntu_image" {
  description = "Multipass image alias for every server"
  type        = string
  default     = "22.04"
}

variable "servers" {
  description = "Per-server sizing (Multipass stand-in for instance type), keyed by role"
  type = map(object({
    cpus   = number
    memory = string
    disk   = string
  }))
  default = {
    api      = { cpus = 1, memory = "1G", disk = "5G" }
    payments = { cpus = 1, memory = "1G", disk = "5G" }
    logs     = { cpus = 1, memory = "1G", disk = "5G" }
  }
}
