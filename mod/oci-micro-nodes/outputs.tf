output "availability_domain" {
  description = "AD, в котором стоят ноды (выбран автоматически или задан явно)"
  value       = local.availability_domain
}

output "image" {
  description = "Платформенный образ, с которого поднимались ноды"
  value       = data.oci_core_images.ubuntu.images[0].display_name
}

output "nodes" {
  value = {
    for name, cfg in var.nodes : name => {
      role        = cfg.role
      instance_id = oci_core_instance.node[name].id
      public_ip   = oci_core_public_ip.node[name].ip_address
      private_ip  = oci_core_instance.node[name].private_ip
    }
  }
}
