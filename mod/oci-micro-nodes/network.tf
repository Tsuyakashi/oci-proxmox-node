# Отдельный VCN под micro-ноды — не пересекается с VCN A1-ноды (10.20/16),
# оба env живут независимо и не задевают друг друга при destroy/apply.
#
# Фильтрация: общее (Tailscale p2p, ICMP PMTUD, аварийный SSH) — в
# security list подсети; ролевые UDP-порты (WG / Valheim) — в NSG
# конкретной ноды, чтобы WG-нода не светила порты Valheim и наоборот.

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_block     = var.vcn_cidr
  display_name   = "oci-micro-vcn"
  dns_label      = "ocimicro"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-micro-igw"
  enabled        = true
}

resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-micro-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-micro-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Tailscale p2p (обе ноды в тайлнете) — прямое соединение вместо DERP.
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "17"
    udp_options {
      min = 41641
      max = 41641
    }
  }

  # ICMP PMTUD (type 3 code 4) — без него MTU-чёрные дыры на WG/Tailscale.
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1"
    icmp_options {
      type = 3
      code = 4
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.ssh_ingress_cidrs
    content {
      source   = ingress_security_rules.value
      protocol = "6"
      tcp_options {
        min = 22
        max = 22
      }
    }
  }
}

resource "oci_core_subnet" "this" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.subnet_cidr
  display_name               = "oci-micro-subnet"
  dns_label                  = "micro"
  route_table_id             = oci_core_route_table.this.id
  security_list_ids          = [oci_core_security_list.this.id]
  prohibit_public_ip_on_vnic = false
}

# --- Ролевые порты: NSG на каждую ноду ---

resource "oci_core_network_security_group" "node" {
  for_each = var.nodes

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${each.key}-nsg"
}

locals {
  nsg_udp_rules = {
    for r in flatten([
      for name, cfg in var.nodes : [
        for p in cfg.udp_ports : { node = name, min = p.min, max = p.max }
      ]
    ]) : "${r.node}-${r.min}-${r.max}" => r
  }
}

resource "oci_core_network_security_group_security_rule" "udp" {
  for_each = local.nsg_udp_rules

  network_security_group_id = oci_core_network_security_group.node[each.value.node].id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  udp_options {
    destination_port_range {
      min = each.value.min
      max = each.value.max
    }
  }
}
