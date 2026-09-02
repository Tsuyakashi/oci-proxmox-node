output "ssh_command" {
  description = "Быстрый доступ по SSH сразу после apply (юзер зависит от образа — opc для Oracle Linux, debian для Debian-образов из marketplace)"
  value       = "ssh debian@${oci_core_instance.pve_node.public_ip}"
}
