output "instance_id" {
  description = "OCID инстанса — для oci compute console-history и прочих CLI-команд"
  value       = oci_core_instance.pve_node.id
}

output "public_ip" {
  description = "Зарезервированный публичный IP — стабилен между пересозданиями инстанса"
  value       = oci_core_public_ip.pve_node.ip_address
}

output "ssh_command" {
  description = "Быстрый доступ по SSH сразу после apply"
  value       = "ssh debian@${oci_core_public_ip.pve_node.ip_address}"
}

output "tailscale_note" {
  value = "Web GUI (8006) закрыт наружу — доступ через Tailscale (см. README), не через public_ip напрямую"
}
