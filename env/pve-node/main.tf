# env/pve-node
#
# Единственный environment этого репо на сегодня — одна OCI ARM-нода под
# Proxmox VE. Вся инфраструктура (сеть/инстанс/диски/reserved IP) — в
# mod/oci-pve-node, здесь только backend/provider (см. backend.tf,
# providers.tf) и передача переменных, ровно тот же паттерн, что
# modules/proxmox-vm + environments/* в iac-proxmox-lab (там папки
# полными словами — здесь сокращено на env/mod).

module "pve_node" {
  source = "../../mod/oci-pve-node"

  compartment_ocid     = var.compartment_ocid
  availability_domain  = var.availability_domain
  image_ocid           = var.image_ocid
  instance_shape       = var.instance_shape
  instance_ocpus       = var.instance_ocpus
  instance_memory_gb   = var.instance_memory_gb
  boot_volume_size_gb  = var.boot_volume_size_gb
  block_volume_size_gb = var.block_volume_size_gb
  hostname             = var.hostname
  ssh_public_key       = var.ssh_public_key
  container_subnet     = var.container_subnet
  pve_version_branch   = var.pve_version_branch
  root_password        = var.root_password
  tailscale_authkey    = var.tailscale_authkey
  vcn_cidr             = var.vcn_cidr
  subnet_cidr          = var.subnet_cidr
}
