# Auth-переменные провайдера сюда не входят — как и в mod/oci-pve-node,
# provider "oci" настраивается только в корневом env.

variable "compartment_ocid" {
  description = "OCID compartment (для Always Free — tenancy OCID)"
  type        = string
}

variable "availability_domain" {
  description = "AD для всех нод. Пусто = первый AD, где шейп вообще доступен тенанси (E2.1.Micro обычно разрешён только в одном AD)."
  type        = string
  default     = ""
}

variable "shape" {
  description = "Always Free x86 шейп. Фиксированный (1/8 OCPU, 1 GB RAM) — shape_config не нужен."
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "ubuntu_version" {
  description = "operating_system_version platform-образа Canonical Ubuntu (берётся самый свежий)."
  type        = string
  default     = "24.04"
}

variable "boot_volume_size_gb" {
  description = "Boot volume на каждую ноду. 50 — минимум OCI; 2x50 = 100 из общих 200 GB Always Free."
  type        = number
  default     = 50
}

variable "ssh_public_key" {
  description = "Содержимое публичного SSH-ключа (не путь)."
  type        = string
}

variable "tailscale_authkey" {
  description = "Reusable Tailscale auth key — одним ключом регистрируются обе ноды. Должен разрешать теги из nodes[*].ts_tags."
  type        = string
  sensitive   = true
}

variable "nodes" {
  description = "Ноды: ключ = hostname. role: wireguard | tailscale."
  type = map(object({
    role              = string
    ts_tags           = string
    udp_ports         = list(object({ min = number, max = number }))
    wg_address        = optional(string, "")
    wg_port           = optional(number, 51820)
    valheim_target_ip = optional(string, "")
  }))

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["wireguard", "tailscale"], n.role)])
    error_message = "nodes[*].role: только wireguard или tailscale."
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : n.role != "wireguard" || n.wg_address != ""])
    error_message = "Для role=wireguard обязателен wg_address (например 10.66.66.1/24)."
  }
}

variable "ssh_ingress_cidrs" {
  description = "Аварийный публичный SSH (22/tcp). По умолчанию закрыт — доступ только через Tailscale. Указать свой /32, если bootstrap упал до tailscale up."
  type        = list(string)
  default     = []
}

variable "vcn_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}
