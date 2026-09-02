output "ssh_command" {
  description = "Быстрый доступ по SSH сразу после apply"
  value       = "ssh debian@${oci_core_public_ip.pve_node.ip_address}"
}
