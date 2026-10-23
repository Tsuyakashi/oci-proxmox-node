# env/micro-nodes
#
# Always-Free x86 нода (VM.Standard.E2.1.Micro) вместо LXC на A1:
#   oci-ts — Tailscale app-connector (smart vpn) + WireGuard-сервер +
#            форвард Valheim. Всё на одной ноде: лимит reserved public IP
#            на тенанси = 1, и он висит на ней.
# Независимо от env/pve-node: свой стейт, свой VCN.
#
# Вторая micro-нода (Always Free даёт две) — в резерве. Если понадобится,
# reserved IP останется на oci-ts, а сервисы второй ноды можно отдавать
# наружу DNAT'ом с oci-ts на её приватный адрес в том же VCN (10.30.1.x).
#
# Диск: 50 GB boot из 200 GB Always Free.

locals {
  nodes = {
    "oci-ts" = {
      role       = "tailscale"
      ts_tags    = "tag:app-connector"
      wg_address = "10.66.66.1/24"
      # Tailscale-IP LXC с Valheim на pve-rog (`tailscale ip -4` внутри
      # контейнера). Пусто — форвард не настраивается.
      valheim_target_ip = ""
      udp_ports = [
        { min = 2456, max = 2458 },   # Valheim
        { min = 51820, max = 51820 }, # WireGuard
      ]
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
