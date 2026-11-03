output "name" {
  description = "VM name"
  value       = null_resource.this.triggers.name
}

output "ip" {
  description = "VM IPv4 address, read from Multipass after launch"
  value       = data.external.ip.result.ip
}
