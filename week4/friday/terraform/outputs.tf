output "server_ips" {
  description = "IPv4 address per server role"
  value       = { for k, m in module.app_server : k => m.ip }
}

output "ssh_commands" {
  description = "Copy-paste SSH command per server"
  value       = { for k, m in module.app_server : k => "ssh -i ~/.ssh/id_rsa ubuntu@${m.ip}" }
}

output "ansible_inventory" {
  description = "Inventory lines ready to write to inventory.ini"
  value       = join("\n", concat(["[kijanikiosk]"], [for k, m in module.app_server : "${m.name} ansible_host=${m.ip}"]))
}
