locals {
  cloud_init_rendered = templatefile("${path.module}/cloud-init/bootstrap.sh.tpl", {
    hostname           = var.hostname
    pve_version_branch = var.pve_version_branch
    container_subnet   = var.container_subnet
    root_password      = var.root_password
    tailscale_authkey  = var.tailscale_authkey
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

  # Публичный IP НЕ назначаем тут (assign_public_ip = false) — вешаем
  # отдельный RESERVED public IP ниже, чтобы адрес не менялся при
  # пересоздании инстанса (эфемерный IP жёстко привязан к инстансу).
  create_vnic_details {
    subnet_id        = oci_core_subnet.this.id
    assign_public_ip = false
    hostname_label   = var.hostname
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init_rendered)
  }

  lifecycle {
    create_before_destroy = false
  }
}

# --- Второй диск под ZFS-пул (container-хранилище), paravirtualized ---

resource "oci_core_volume" "zfs_data" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = "${var.hostname}-zfs-data"
  size_in_gbs         = var.block_volume_size_gb
}

resource "oci_core_volume_attachment" "zfs_data" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.pve_node.id
  volume_id       = oci_core_volume.zfs_data.id
  # is_pv_encryption_in_transit_enabled по умолчанию false — совпадает
  # с launchOptions.isPvEncryptionInTransitEnabled=false, заданным при
  # импорте образа (см. scripts/import-debian-image.py); рассинхрон
  # между этими двумя флагами не тестировался апстримом.
}

# --- Зарезервированный публичный IP, не эфемерный ---
# Эфемерный IP умирает вместе с VNIC при любом пересоздании инстанса —
# для ноды, на которую будешь показывать Tailscale route и держать
# постоянный SSH-доступ, это не тот случай, где адрес можно терять.

data "oci_core_vnic_attachments" "pve_node" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.pve_node.id
}

# oci_core_vnic не отдаёт OCID приватного IP напрямую (только сам адрес),
# а oci_core_public_ip.private_ip_id требует именно OCID объекта — нужен
# отдельный data source.
data "oci_core_private_ips" "pve_node" {
  vnic_id = data.oci_core_vnic_attachments.pve_node.vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "pve_node" {
  compartment_id = var.compartment_ocid
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.pve_node.private_ips[0].id
  display_name   = "${var.hostname}-reserved-ip"
}
