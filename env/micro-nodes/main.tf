# env/micro-nodes
#
# Две Always-Free x86 ноды (VM.Standard.E2.1.Micro) вместо LXC на A1:
#   oci-wg — WireGuard-сервер
#   oci-ts — Tailscale app-connector (smart vpn) + форвард Valheim
# Независимы от env/pve-node: свой стейт, свой VCN.
#
# Диск: 2 x 50 GB boot = 100 из 200 GB Always Free. Если A1 когда-нибудь
# поймается — в oci/config ужать его до 100 GB суммарно
# (boot_volume_size_gb + block_volume_size_gb).

locals {
  nodes = {
    "oci-wg" = {
      role = "wireguard"
      # Тот же тег, что у app-connector'а: authkey в Vault выпущен под него,
      # отдельный тег (tag:wg) потребует нового ключа + tagOwners в
      # tailscale-acl. --advertise-connector на этой ноде НЕ ставится,
      # так что коннектором она не становится.
      ts_tags    = "tag:app-connector"
      wg_address = "10.66.66.1/24"
      udp_ports  = [{ min = 51820, max = 51820 }]
    }

    "oci-ts" = {
      role    = "tailscale"
      ts_tags = "tag:app-connector"
      # Tailscale-IP LXC с Valheim на pve-rog (`tailscale ip -4` внутри
      # контейнера). Пусто — форвард не настраивается.
      valheim_target_ip = ""
      udp_ports         = [{ min = 2456, max = 2458 }]
    }
  }
}

module "micro_nodes" {
  source = "../../mod/oci-micro-nodes"

  compartment_ocid    = var.compartment_ocid
  availability_domain = var.micro_availability_domain
  ssh_public_key      = var.ssh_public_key
  tailscale_authkey   = var.tailscale_authkey
  nodes               = local.nodes
  vcn_cidr            = var.vcn_cidr
  subnet_cidr         = var.subnet_cidr
}
