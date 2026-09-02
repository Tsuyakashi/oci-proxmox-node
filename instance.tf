locals {
  cloud_init_rendered = templatefile("${path.module}/cloud-init/bootstrap.sh.tpl", {
    hostname           = var.hostname
    pve_version_branch = var.pve_version_branch
  })
}

resource "oci_core_instance" "pve_node" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = var.hostname
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.this.id
    assign_public_ip = true
    hostname_label   = var.hostname
  }

  source_details {
    source_type = "image"
    source_id   = var.image_ocid
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data           = base64encode(local.cloud_init_rendered)
  }

  # Полная переустановка при смене bootstrap-скрипта — намеренно,
  # это разовый bare-install, а не идемпотентный конфиг-менеджмент.
  lifecycle {
    create_before_destroy = false
  }
}

output "public_ip" {
  description = "Публичный IP новой ноды — им же и подключаться (web GUI :8006, ssh)"
  value       = oci_core_instance.pve_node.public_ip
}

output "pve_web_gui" {
  value = "https://${oci_core_instance.pve_node.public_ip}:8006"
}
