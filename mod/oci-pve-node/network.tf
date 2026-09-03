# Security list: TCP-ingress нет вообще — ни 22, ни 8006. Весь доступ к
# ноде идёт через Tailscale (overlay), см. bootstrap.sh.tpl шаг с
# tailscale up --advertise-routes. Открыты только Tailscale UDP-порт
# (прямые p2p-соединения вместо relay через DERP) и ICMP (path MTU
# discovery).

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_block     = var.vcn_cidr
  display_name   = "oci-proxmox-node-vcn"
  dns_label      = "ocipvevcn"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-proxmox-node-igw"
  enabled        = true
}

resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-proxmox-node-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "oci-proxmox-node-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Tailscale — UDP 41641, даёт прямое p2p-соединение вместо relay через
  # DERP-серверы Tailscale (медленнее и лишняя зависимость от их аптайма).
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "17" # UDP
    udp_options {
      min = 41641
      max = 41641
    }
  }

  # ICMP path MTU discovery (type 3 = destination unreachable, code 4 =
  # fragmentation needed) — без этого черные дыры на MTU-чувствительном
  # трафике (в частности сам Tailscale/WireGuard).
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "this" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.subnet_cidr
  display_name               = "oci-proxmox-node-subnet"
  dns_label                  = "ocipvesub"
  route_table_id             = oci_core_route_table.this.id
  security_list_ids          = [oci_core_security_list.this.id]
  prohibit_public_ip_on_vnic = false
}
