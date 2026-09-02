# --- OCI auth (в Vault, secret/oci-proxmox-node/*) ---

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
  description = "Путь до временного файла с приватным ключом API (PEM). Заполняется автоматически scripts/vault-apply-wrapper.sh из secret/oci-proxmox-node/api — дефолта намеренно нет, чтобы apply не прошёл молча без Vault"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Регион OCI (например eu-frankfurt-1)"
  type        = string
}

# --- Compartment / networking ---

variable "compartment_ocid" {
  description = "OCID compartment, в котором создаются ресурсы"
  type        = string
}

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

# Порты, которые нужно открыть наружу помимо SSH.
# 8006 — PVE web GUI, 5405/udp — corosync knet (если решишь тянуть link1 из прошлого обсуждения)
variable "ingress_ports_tcp" {
  description = "Список TCP-портов, открываемых на публичный интернет"
  type        = list(number)
  default     = [22, 8006]
}

variable "ingress_ports_udp" {
  description = "Список UDP-портов (например corosync knet), открываемых на публичный интернет"
  type        = list(number)
  default     = []
}

# --- Instance ---

variable "availability_domain" {
  description = "AD, в котором создаётся инстанс (см. `oci iam availability-domain list`)"
  type        = string
}

variable "instance_shape" {
  description = "Shape инстанса. VM.Standard.A1.Flex — ARM/Ampere always-free (без nested virt, только LXC). VM.Standard.E2.1.Micro — x86 always-free, крошечный."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Кол-во OCPU (актуально для Flex-шейпов). Always-free потолок сейчас — 2 OCPU суммарно на все Ampere-инстансы."
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Память в GB (актуально для Flex-шейпов). Always-free потолок сейчас — 12GB суммарно."
  type        = number
  default     = 12
}

variable "image_ocid" {
  description = "OCID образа Debian 12 (bookworm) aarch64 для Ampere A1, см. `oci compute image list --operating-system Debian`. ОБЯЗАТЕЛЬНО Debian, не Ubuntu — см. cloud-init/bootstrap.sh.tpl"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Путь до публичного SSH-ключа для доступа opc@<ip>"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "hostname" {
  description = "Hostname будущей PVE-ноды"
  type        = string
  default     = "oci-pve"
}

variable "pve_version_branch" {
  description = "Ветка репозитория Proxmox VE (bookworm для Debian 12 / Ubuntu 24.04 базы)"
  type        = string
  default     = "bookworm"
}
