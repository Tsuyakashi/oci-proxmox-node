output "availability_domain" {
  value = module.micro_nodes.availability_domain
}

output "image" {
  value = module.micro_nodes.image
}

output "nodes" {
  value = module.micro_nodes.nodes
}

output "access_note" {
  value = "22/tcp наружу закрыт: ssh ubuntu@oci-wg / ubuntu@oci-ts через тайлнет. Лог бутстрапа: /var/log/node-bootstrap.log"
}
