# Все переменные ниже приходят через TF_VAR_* из scripts/vault-apply-wrapper.sh
# (oci/api — секреты, oci/config — остальной конфиг). Никаких дефолтов
# намеренно нет нигде, кроме vcn_cidr/subnet_cidr (чисто топология адресации,
# не тянется из Vault, менять вручную здесь при необходимости) — apply без
# Vault должен падать с "No value for required variable", а не тихо
# подхватывать что-то с диска.

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
  description = "Путь до временного файла с приватным ключом API (PEM). Заполняется scripts/vault-apply-wrapper.sh из oci/api — сам ключ хранится в Vault целиком, файл в /tmp только на время сессии шелла"
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
  description = "OCID образа Debian 12 (bookworm) aarch64 для Ampere A1, см. `oci compute image list --operating-system Debian`. ОБЯЗАТЕЛЬНО Debian, не Ubuntu — см. cloud-init/bootstrap.sh.tpl"
  type        = string
}

variable "instance_shape" {
  description = "Shape инстанса. VM.Standard.A1.Flex — ARM/Ampere always-free (без nested virt, только LXC). VM.Standard.E2.1.Micro — x86 always-free, крошечный."
  type        = string
}

variable "instance_ocpus" {
  description = "Кол-во OCPU (актуально для Flex-шейпов). Always-free потолок сейчас — 2 OCPU суммарно на все Ampere-инстансы."
  type        = number
}

variable "instance_memory_gb" {
  description = "Память в GB (актуально для Flex-шейпов). Always-free потолок сейчас — 12GB суммарно."
  type        = number
}

variable "hostname" {
  description = "Hostname будущей PVE-ноды"
  type        = string
}

variable "ssh_public_key" {
  description = "Содержимое публичного SSH-ключа (не путь!) для доступа к инстансу. Хранится в oci/config как есть — сам ключ не секретен, но так убирается последняя зависимость от локального файла/пути на диске."
  type        = string
}

variable "ingress_ports_tcp" {
  description = "Список TCP-портов, открываемых на публичный интернет. Приходит из oci/config как HCL-литерал строкой, например \"[22, 8006]\""
  type        = list(number)
}

variable "ingress_ports_udp" {
  description = "Список UDP-портов (например corosync knet), открываемых на публичный интернет. Приходит из oci/config тем же способом."
  type        = list(number)
}

variable "pve_version_branch" {
  description = "Ветка репозитория Proxmox VE (bookworm для Debian 12 / Ubuntu 24.04 базы)"
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
