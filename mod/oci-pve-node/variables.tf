# Auth-переменные провайдера (tenancy/user/fingerprint/private_key_path)
# сюда НЕ входят — provider "oci" настраивается только в корневом
# environment (env/pve-node/providers.tf), модуль про это ничего
# не знает, только про сами ресурсы.

variable "compartment_ocid" {
  description = "OCID compartment, в котором создаются ресурсы"
  type        = string
}

variable "availability_domain" {
  description = "AD, в котором создаётся инстанс"
  type        = string
}

variable "image_ocid" {
  description = "OCID custom-образа Debian 13 (trixie) arm64, импортированного через scripts/import-debian-image.py (launchMode=CUSTOM, firmware=UEFI_64)."
  type        = string
}

variable "instance_shape" {
  description = "Shape инстанса. VM.Standard.A1.Flex — ARM/Ampere always-free. Не даёт EL2 -> только LXC-контейнеры, никаких QEMU VM."
  type        = string
}

variable "instance_ocpus" {
  description = "Кол-во OCPU."
  type        = number
}

variable "instance_memory_gb" {
  description = "Память в GB."
  type        = number
}

variable "boot_volume_size_gb" {
  description = "Размер boot volume — становится Proxmox datastore 'local'."
  type        = number
}

variable "block_volume_size_gb" {
  description = "Размер отдельного block volume (paravirtualized) — становится ZFS-пул 'tank'."
  type        = number
}

variable "hostname" {
  description = "Hostname будущей PVE-ноды. Proxmox зашивает его в /etc/pve/nodes/<name>/ — выбирать окончательно сразу."
  type        = string
}

variable "ssh_public_key" {
  description = "Содержимое публичного SSH-ключа (не путь!) для доступа к инстансу."
  type        = string
}

variable "container_subnet" {
  description = "Внутренняя NAT-подсеть для LXC-контейнеров на vmbr0. CIDR, например \"10.10.10.0/24\"."
  type        = string
}

variable "pve_version_branch" {
  description = "Ветка репозитория Proxmox VE. 'trixie' для Debian 13 — ARM-сборка PVE существует только под неё."
  type        = string
}

variable "root_password" {
  description = "Пароль root для веб-GUI Proxmox (realm Linux PAM). SSH по-прежнему только по ключу."
  type        = string
  sensitive   = true
}

variable "tailscale_authkey" {
  description = "Tailscale auth key (Settings -> Keys). Даёт unattended `tailscale up`; одобрение advertised route всё равно нужно руками в admin-консоли."
  type        = string
  sensitive   = true
}

variable "vcn_cidr" {
  description = "CIDR для VCN"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR для публичного subnet"
  type        = string
}
