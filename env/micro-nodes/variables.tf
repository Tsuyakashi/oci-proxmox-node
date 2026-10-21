# Секреты и общий конфиг — те же TF_VAR_*, что tf-secrets уже экспортирует
# для oci-proxmox-node (oci/api + oci/config). A1-специфичные TF_VAR_*
# (image_ocid, instance_shape, ...) здесь не объявлены — Terraform
# необъявленные env-переменные молча игнорирует.

# --- OCI auth (Vault: oci/api) ---

variable "tenancy_ocid" {
  type      = string
  sensitive = true
}

variable "user_ocid" {
  type      = string
  sensitive = true
}

variable "fingerprint" {
  type      = string
  sensitive = true
}

variable "oci_private_key_path" {
  type      = string
  sensitive = true
}

variable "tailscale_authkey" {
  description = "Reusable key с правом на tag:app-connector — регистрирует обе ноды"
  type        = string
  sensitive   = true
}

# --- Общий конфиг (Vault: oci/config) ---

variable "region" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

# --- Топология, не секрет и не из Vault ---

variable "micro_availability_domain" {
  description = "Пусто = автоматически первый AD, где E2.1.Micro доступен тенанси"
  type        = string
  default     = ""
}

variable "vcn_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.30.1.0/24"
}
