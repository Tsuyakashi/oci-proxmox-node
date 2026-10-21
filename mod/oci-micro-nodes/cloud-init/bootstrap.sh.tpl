#!/bin/bash
# Bootstrap Always-Free VM.Standard.E2.1.Micro (x86, 1 GB RAM) под одну роль:
#   wireguard — WG-сервер (wg-quick@wg0); Tailscale только для SSH/админки
#   tailscale — Tailscale app-connector (smart vpn) + опциональный UDP-форвард
#               Valheim на LXC на pve-rog через тайлнет
#
# Рендерится templatefile() из instance.tf, cloud-init выполняет один раз.
# Экранирование: двойной доллар перед фигурной скобкой -> bash-переменная,
# одинарный -> значение из Terraform (templatefile).

set -euxo pipefail
exec > >(tee -a /var/log/node-bootstrap.log) 2>&1
echo "=== bootstrap ${hostname} (role=${role}): $(date) ==="

export DEBIAN_FRONTEND=noninteractive

# --- swap: 1 GB RAM впритык для apt + tailscaled ---
if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- Oracle-образы Ubuntu идут с /etc/iptables/rules.v4, где INPUT режет
# всё, кроме 22/tcp, а FORWARD — REJECT целиком (грузится
# netfilter-persistent на каждом буте). Для WG и app-connector это смерть
# форвардинга. Фильтрация и так на уровне VCN (security list + NSG),
# поэтому на хосте — открытый baseline, и он же персистится. ---
mkdir -p /etc/iptables
cat >/etc/iptables/rules.v4 <<'EOF'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
EOF
iptables-restore < /etc/iptables/rules.v4

# --- apt: IPv4-only + без интерактивных конфликтов конфигов ---
cat >/etc/apt/apt.conf.d/99bootstrap-unattended <<'EOF'
Acquire::ForceIPv4 "true";
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
EOF

# Ждём реальный выход в интернет, не только DNS: reserved IP цепляется к
# VNIC уже ПОСЛЕ создания инстанса, cloud-init может стартовать раньше.
NET_READY=0
for _ in $(seq 1 60); do
    if curl -4 -fsS -o /dev/null --max-time 5 https://pkgs.tailscale.com; then
        NET_READY=1
        break
    fi
    sleep 5
done
if [ "$${NET_READY}" -ne 1 ]; then
    echo "FATAL: нет выхода в интернет за 5 минут" >&2
    exit 1
fi

apt-get update -qq
apt-get install -y -qq ethtool

cat >/etc/sysctl.d/99-forward.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system

PRIMARY_IF=$(ip -4 route show default | awk '{print $5; exit}')

%{ if role == "wireguard" ~}
# ============================ WireGuard ============================
# Приватный ключ генерируется НА ХОСТЕ и никогда не попадает ни в
# Terraform state, ни в Vault. Пиры — руками (см. docs/micro-nodes.md).
apt-get install -y -qq wireguard-tools

umask 077
mkdir -p /etc/wireguard
[ -f /etc/wireguard/server.key ] || wg genkey > /etc/wireguard/server.key
wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub

if [ ! -f /etc/wireguard/wg0.conf ]; then
    cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${wg_address}
ListenPort = ${wg_port}
PrivateKey = $(cat /etc/wireguard/server.key)
PostUp = iptables -t nat -A POSTROUTING -o $${PRIMARY_IF} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o $${PRIMARY_IF} -j MASQUERADE
EOF
fi
umask 022

systemctl enable --now wg-quick@wg0
echo "WG server pubkey: $(cat /etc/wireguard/server.pub)"

TS_EXTRA=""
%{ endif ~}
%{ if role == "tailscale" ~}
# ===================== Tailscale app-connector =====================
TS_EXTRA="--advertise-connector"

cat >/etc/systemd/system/tailscale-tweaks.service <<EOF
[Unit]
Description=Tailscale app-connector forwarding tweaks
After=tailscaled.service network-online.target
Wants=tailscaled.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ethtool -K $${PRIMARY_IF} rx-udp-gro-forwarding on rx-gro-list off

[Install]
WantedBy=multi-user.target
EOF
%{ endif ~}

# ============================ Tailscale ============================
# На обеих нодах: на WG-ноде — только для SSH/админки (22/tcp наружу
# закрыт), на tailscale-ноде — app-connector для smart-vpn-users.
curl -4 -fsSL https://tailscale.com/install.sh | sh

tailscale up --authkey="${tailscale_authkey}" \
    --advertise-tags="${ts_tags}" \
    --hostname="${hostname}" \
    --accept-dns=false \
    $${TS_EXTRA}

%{ if role == "tailscale" ~}
systemctl daemon-reload
systemctl enable --now tailscale-tweaks.service
%{ if valheim_target_ip != "" ~}

# ===================== Valheim UDP-форвард =====================
# Публичный UDP 2456-2458 на reserved IP этой ноды -> LXC с сервером на
# pve-rog по его tailscale-адресу. MASQUERADE на tailscale0 — чтобы ответы
# шли обратно через эту ноду (грант tag:app-connector -> tag:game в
# tailscale-acl).
cat >/usr/local/sbin/valheim-forward.sh <<'EOF'
#!/bin/bash
set -eu
IF=$(ip -4 route show default | awk '{print $5; exit}')
for _ in $(seq 1 60); do
    ip link show tailscale0 >/dev/null 2>&1 && break
    sleep 1
done
add() { iptables -t nat -C "$@" 2>/dev/null || iptables -t nat -A "$@"; }
add PREROUTING -i "$${IF}" -p udp --dport 2456:2458 -j DNAT --to-destination ${valheim_target_ip}
add POSTROUTING -o tailscale0 -p udp -d ${valheim_target_ip} --dport 2456:2458 -j MASQUERADE
EOF
chmod 755 /usr/local/sbin/valheim-forward.sh

cat >/etc/systemd/system/valheim-forward.service <<'EOF'
[Unit]
Description=Valheim UDP forward to game LXC via tailnet
After=tailscaled.service network-online.target
Wants=tailscaled.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/valheim-forward.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now valheim-forward.service
%{ endif ~}
%{ endif ~}

echo "=== bootstrap ${hostname} DONE: $(date) ==="
