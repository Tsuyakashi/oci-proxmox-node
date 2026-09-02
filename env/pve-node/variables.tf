# Все переменные ниже приходят через TF_VAR_* из scripts/vault-apply-wrapper.sh
# (oci/api — секреты, oci/config — остальной конфиг). Никаких дефолтов
# намеренно нет нигде, кроме vcn_cidr/subnet_cidr (чисто топология адресации) —
# apply без Vault должен падать с "No value for required variable".

# --- OCI auth (Vault: oci/api) ---

variable "tenancy_ocid" {
  description = "OCID тенанси OCI"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCID пользователя API-ключа"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "Fingerprint публичного API-ключа"
  type        = string
  sensitive   = true
}

variable "oci_private_key_path" {
  description = "Путь до временного файла с приватным ключом API (PEM). Заполняется scripts/vault-apply-wrapper.sh из oci/api"
  type        = string
  sensitive   = true
}

variable "root_password" {
  description = "Пароль root для веб-GUI Proxmox (realm Linux PAM). SSH по-прежнему только по ключу — этот пароль только для https://<tailscale-ip>:8006"
  type        = string
  sensitive   = true
}

variable "tailscale_authkey" {
  description = "Tailscale auth key (Settings -> Keys в консоли Tailscale) — даёт unattended `tailscale up` без ручного логина. Одобрение advertised route (container_subnet) всё равно нужно сделать руками в admin-консоли один раз."
  type        = string
  sensitive   = true
}

# --- Остальной конфиг (Vault: oci/config) ---

variable "region" {
  description = "Регион OCI (например eu-frankfurt-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID compartment, в котором создаются ресурсы"
  type        = string
}

variable "availability_domain" {
  description = "AD, в котором создаётся инстанс (см. `oci iam availability-domain list`)"
  type        = string
}

variable "image_ocid" {
  description = "OCID custom-образа Debian 13 (trixie) arm64, импортированного через scripts/import-debian-image.py (launchMode=CUSTOM, firmware=UEFI_64). НЕ platform image — Oracle не публикует Debian как готовый образ, см. README."
  type        = string
}

variable "instance_shape" {
  description = "Shape инстанса. VM.Standard.A1.Flex — ARM/Ampere always-free. Не даёт EL2 -> только LXC-контейнеры, никаких QEMU VM (см. README)."
  type        = string
}

variable "instance_ocpus" {
  description = "Кол-во OCPU. Always-free потолок сейчас — 2 OCPU суммарно на все Ampere-инстансы."
  type        = number
}

variable "instance_memory_gb" {
  description = "Память в GB. Always-free потолок сейчас — 12GB суммарно."
  type        = number
}

variable "boot_volume_size_gb" {
  description = "Размер boot volume — становится Proxmox datastore 'local' (шаблоны/бэкапы). 60GB по гайду."
  type        = number
}

variable "block_volume_size_gb" {
  description = "Размер отдельного block volume (paravirtualized) — становится ZFS-пул 'tank' под контейнеры. 140GB по гайду (60+140=200GB укладывается в free-tier block storage allowance)."
  type        = number
}

variable "hostname" {
  description = "Hostname будущей PVE-ноды. Proxmox зашивает его в /etc/pve/nodes/<name>/ — переименование задним числом мучительно (см. README), выбирать сразу окончательно."
  type        = string
}

variable "ssh_public_key" {
  description = "Содержимое публичного SSH-ключа (не путь!) для доступа к инстансу."
  type        = string
}

variable "container_subnet" {
  description = "Внутренняя NAT-подсеть для LXC-контейнеров на vmbr0 (без физического порта — OCI vNIC пропускает только свой MAC, прямой бридж на физический интерфейс не пропустит трафик гостей). Формат CIDR, например \"10.10.10.0/24\"."
  type        = string
}

variable "pve_version_branch" {
  description = "Ветка репозитория Proxmox VE. 'trixie' для Debian 13 — ARM-сборка PVE официально существует только под неё, НЕ bookworm."
  type        = string
}

# --- Топология адресации, не секрет и не тянется из Vault ---

variable "vcn_cidr" {
  description = "CIDR для VCN"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR для публичного subnet"
  type        = string
  default     = "10.20.1.0/24"
}
