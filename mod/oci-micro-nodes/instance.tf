# --- AD: E2.1.Micro у тенанси обычно разрешён только в одном AD региона.
# Если var.availability_domain пуст — берём первый AD, где шейп есть в
# списке доступных. ---

data "oci_identity_availability_domains" "this" {
  compartment_id = var.compartment_ocid
}

data "oci_core_shapes" "per_ad" {
  for_each = toset([for ad in data.oci_identity_availability_domains.this.availability_domains : ad.name])

  compartment_id      = var.compartment_ocid
  availability_domain = each.key
}

locals {
  shape_ads           = [for ad, s in data.oci_core_shapes.per_ad : ad if contains([for sh in s.shapes : sh.name], var.shape)]
  availability_domain = var.availability_domain != "" ? var.availability_domain : try(local.shape_ads[0], "")
}

# --- Образ: обычный platform image (x86), никакого ручного импорта, как
# у A1. Берётся самый свежий; последующие обновления образа НЕ пересоздают
# ноду (ignore_changes ниже). ---

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = var.ubuntu_version
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "node" {
  for_each = var.nodes

  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = each.key
  shape               = var.shape

  # Публичный IP — отдельным RESERVED ресурсом ниже, не эфемерным.
  create_vnic_details {
    subnet_id        = oci_core_subnet.this.id
    assign_public_ip = false
    hostname_label   = each.key
    nsg_ids          = [oci_core_network_security_group.node[each.key].id]
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init/bootstrap.sh.tpl", {
      hostname          = each.key
      role              = each.value.role
      ts_tags           = each.value.ts_tags
      tailscale_authkey = var.tailscale_authkey
      wg_address        = each.value.wg_address
      wg_port           = each.value.wg_port
      valheim_target_ip = each.value.valheim_target_ip
    }))
  }

  lifecycle {
    # Новый образ Canonical или правка bootstrap/секрета не должны молча
    # пересоздавать живую ноду (и терять слот capacity). Пересборка —
    # только явно:
    #   terraform apply -replace='module.micro_nodes.oci_core_instance.node["oci-wg"]'
    ignore_changes = [
      source_details[0].source_id,
      metadata["user_data"],
    ]

    precondition {
      condition     = local.availability_domain != ""
      error_message = "Не найден AD, где доступен ${var.shape}. Задай availability_domain явно."
    }

    precondition {
      condition     = length(data.oci_core_images.ubuntu.images) > 0
      error_message = "Не найден platform image Canonical Ubuntu ${var.ubuntu_version} под ${var.shape}."
    }
  }
}

# --- Reserved public IP на каждую ноду ---
# prevent_destroy — урок с A1: destroy стека снёс reserved IP вместе с
# инстансом, адрес (на него смотрят WG-клиенты и игроки Valheim) потерян
# навсегда. Теперь `terraform destroy` упадёт на этих ресурсах — это
# намеренно. Снести по-настоящему: убрать prevent_destroy руками.

data "oci_core_vnic_attachments" "node" {
  for_each = var.nodes

  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.node[each.key].id
}

# oci_core_public_ip.private_ip_id требует OCID объекта private IP, а не
# адрес — отдельный data source, как в mod/oci-pve-node.
data "oci_core_private_ips" "node" {
  for_each = var.nodes

  vnic_id = data.oci_core_vnic_attachments.node[each.key].vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "node" {
  for_each = var.nodes

  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.node[each.key].private_ips[0].id
  display_name   = "${each.key}-reserved-ip"

  lifecycle {
    prevent_destroy = true
  }
}
