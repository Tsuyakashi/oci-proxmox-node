output "instance_id" {
  description = "OCID инстанса — для oci compute console-history и прочих CLI-команд"
  value       = module.pve_node.instance_id
}

output "public_ip" {
  description = "Зарезервированный публичный IP — стабилен между пересозданиями инстанса"
  value       = module.pve_node.public_ip
}

output "ssh_command" {
  value = module.pve_node.ssh_command
}

output "tailscale_note" {
  value = module.pve_node.tailscale_note
}
