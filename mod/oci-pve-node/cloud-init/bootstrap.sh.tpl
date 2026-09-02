#!/bin/bash
# Bootstrap Proxmox VE ARM64 (официальная поддержка с августа 2026) поверх
# custom-образа Debian 13 (trixie) arm64, импортированного отдельно через
# scripts/import-debian-image.py. Источник рецепта, проверено на
# pve-manager/9.2.9 / VM.Standard.A1.Flex:
# https://www.dima.pm/proxmox-ve-9-2-arm64-on-oracle-cloud/
#
# Двухстадийный: смена ядра требует ребута, поэтому вторая половина работы
# (Proxmox install, storage, сеть, Tailscale) идёт systemd-юнитом, который
# сам себя отключает после первого успешного запуска на новом ядре.
#
# cloud-init выполняет user_data-скрипт РОВНО ОДИН РАЗ (не на каждом
# ребуте) — поэтому stage2 не может быть просто "продолжением" этого же
# скрипта, только отдельный systemd oneshot.

set -euxo pipefail
exec > >(tee -a /var/log/pve-bootstrap.log) 2>&1

echo "=== STAGE 1: $(date) ==="

# --- Хостнейм: preserve, не давать cloud-init перезаписывать на будущих
# ребутах, но сетевую часть cloud-init оставляем как есть (страховка на
# машине, к которой только SSH-доступ) ---
cat >/etc/cloud/cloud.cfg.d/99-pve.cfg <<'EOF'
preserve_hostname: true
manage_etc_hosts: false
EOF

hostnamectl set-hostname "${hostname}"

# Proxmox требует, чтобы hostname резолвился в НЕ-loopback IPv4 —
# публичный IP на OCI никогда не появляется на интерфейсе (1:1 NAT),
# берём приватный адрес vNIC.
PRIMARY_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
PRIV=$(ip -4 -o addr show "$PRIMARY_IF" | awk '{print $4}' | cut -d/ -f1)

cat >/etc/hosts <<EOF
127.0.0.1	localhost
$${PRIV}	${hostname}.local ${hostname}

::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

# --- Репозиторий Proxmox VE (trixie — Debian 13, НЕ bookworm) ---
wget -q https://enterprise.proxmox.com/debian/proxmox-archive-keyring-${pve_version_branch}.gpg \
     -O /usr/share/keyrings/proxmox-archive-keyring.gpg

cat >/etc/apt/sources.list.d/pve-install-repo.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${pve_version_branch}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

apt-get update -qq

if ! apt-cache policy proxmox-ve | grep -q "arm64 Packages"; then
    echo "FATAL: proxmox-ve arm64 candidate не найден в репозитории — проверь pve_version_branch" >&2
    exit 1
fi

# --- Смена ядра: MODULES=most (cloud-образ по умолчанию MODULES=dep —
# только драйверы под железо, присутствовавшее на момент сборки образа) ---
sed -i 's/^MODULES=.*/MODULES=most/' /etc/initramfs-tools/initramfs.conf

sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
apt-get install -y -qq proxmox-default-kernel
update-grub

CFG=/boot/grub/grub.cfg
SUBMENU=$(grep -oP "^submenu '[^']*' \$menuentry_id_option '\K[^']+" "$${CFG}" | head -1)

PVE_ENTRY=""
DEB_ENTRY=""
while read -r e; do
  case "$e" in
    gnulinux-advanced-*) continue ;;
    *pve*) [ -z "$${PVE_ENTRY}" ] && PVE_ENTRY="$e" ;;
    *)     [ -z "$${DEB_ENTRY}" ] && DEB_ENTRY="$e" ;;
  esac
done < <(grep -oP "\$menuentry_id_option '\K[^']*-advanced-[^']*" "$${CFG}")

grub-set-default "$${SUBMENU}>$${DEB_ENTRY}"   # persistent fallback — если pve-ядро не взлетит, следующий обычный ребут вернёт Debian
grub-reboot      "$${SUBMENU}>$${PVE_ENTRY}"   # one-shot — следующий (и только следующий) ребут грузит pve-ядро

# --- systemd-юнит под stage2, сработает ПОСЛЕ ребута на новом ядре ---
cat >/usr/local/sbin/pve-bootstrap-stage2.sh <<'STAGE2EOF'
#!/bin/bash
set -euxo pipefail
exec > >(tee -a /var/log/pve-bootstrap.log) 2>&1
echo "=== STAGE 2: $(date) ==="
echo "kernel: $(uname -r)"

if ! uname -r | grep -q pve; then
    echo "FATAL: не на pve-ядре после ребута (uname -r: $(uname -r))." >&2
    echo "Возможные причины: grub one-shot не сработал, или ядро не взлетело" >&2
    echo "и произошёл автоматический откат на persistent-fallback (Debian)." >&2
    echo "Boot volume backup из консоли OCI — safety net на этот случай." >&2
    exit 1
fi

# --- Установка Proxmox поверх уже поднятого pve-ядра ---
mkdir -p /etc/network/interfaces.d
cat >/etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

source /etc/network/interfaces.d/*
EOF

# postfix спросит интерактивно без debconf preseed — форсируем Local only
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq proxmox-ve postfix chrony
apt-get remove -y -qq linux-image-arm64 linux-image-cloud-arm64 os-prober || true

sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
update-grub

echo "root:__ROOT_PASSWORD__" | chpasswd
echo 'Enabled: false' >> /etc/apt/sources.list.d/pve-enterprise.sources

# --- Storage: второй диск (block volume, paravirtualized) -> ZFS 'tank' ---
DISK=""
for d in /dev/disk/by-id/*; do
    case "$d" in *-part*) continue ;; esac
    if [ "$(readlink -f "$d")" = /dev/sdb ]; then
        DISK="$d"
        break
    fi
done
if [ -z "$${DISK}" ]; then
    echo "FATAL: не нашёл /dev/sdb под ZFS — проверь, что block volume attached (oci_core_volume_attachment применился?)" >&2
    exit 1
fi

zpool create -f -o ashift=12 \
  -O compression=zstd -O atime=off -O xattr=sa -O acltype=posixacl \
  tank "$${DISK}"

echo "options zfs zfs_arc_max=2147483648" >/etc/modprobe.d/zfs.conf
update-initramfs -u -k all

pvesm add zfspool tank --pool tank --content rootdir,images

# --- Сеть контейнеров: NAT-мост без физического порта (OCI vNIC
# принимает трафик только со своим MAC — прямой bridge на физический
# интерфейс не пропустит гостевой трафик) ---
PRIMARY_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v -E '^(lo|vmbr)' | head -n1)
BRIDGE_ADDR=$(echo "${container_subnet}" | awk -F'[./]' '{print $1"."$2"."$3".1"}')

cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto vmbr0
iface vmbr0 inet static
    address $${BRIDGE_ADDR}/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    mtu 1500
    post-up   sysctl -qw net.ipv4.ip_forward=1
    post-up   iptables -t nat -A POSTROUTING -s '${container_subnet}' -o $${PRIMARY_IF} -j MASQUERADE
    post-up   iptables -t nat -A POSTROUTING -s '${container_subnet}' -o tailscale0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s '${container_subnet}' -o tailscale0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s '${container_subnet}' -o $${PRIMARY_IF} -j MASQUERADE
    post-up   iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
    post-down iptables -t raw -D PREROUTING -i fwbr+ -j CT --zone 1

source /etc/network/interfaces.d/*
EOF

mkdir -p /run/network
echo "d /run/network 0755 root root -" > /etc/tmpfiles.d/ifupdown2-network.conf
ifreload -a

# --- DHCP для контейнеров на этом мосту ---
apt-get install -y -qq dnsmasq

cat >/etc/dnsmasq.d/vmbr0.conf <<EOF
interface=vmbr0
bind-interfaces
except-interface=lo
listen-address=$${BRIDGE_ADDR}

dhcp-range=$(echo "${container_subnet}" | awk -F'[./]' '{print $1"."$2"."$3}').100,$(echo "${container_subnet}" | awk -F'[./]' '{print $1"."$2"."$3}').200,12h
dhcp-option=option:router,$${BRIDGE_ADDR}
dhcp-option=option:dns-server,$${BRIDGE_ADDR}
dhcp-authoritative

no-resolv
server=1.1.1.1
server=1.0.0.1

domain=lxc
local=/lxc/
expand-hosts
EOF

systemctl enable --now dnsmasq

timedatectl show --property=Timezone --value > /etc/timezone 2>/dev/null || echo "UTC" > /etc/timezone

# --- Tailscale: remote-доступ к веб-GUI вместо открытия 8006 наружу ---
curl -fsSL https://tailscale.com/install.sh | sh

TAILSCALE_AUTHKEY_VAL="__TAILSCALE_AUTHKEY__"
if [ -n "$${TAILSCALE_AUTHKEY_VAL}" ]; then
    tailscale up --authkey="$${TAILSCALE_AUTHKEY_VAL}" \
        --advertise-routes="${container_subnet}" --accept-routes \
        --accept-dns=false --hostname="${hostname}"
else
    echo "WARNING: TAILSCALE_AUTHKEY не задан — tailscale up не выполнен автоматически." >&2
    echo "Выполни руками: tailscale up --advertise-routes=${container_subnet} --accept-routes --accept-dns=false --hostname=${hostname}" >&2
fi

printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' \
  > /etc/sysctl.d/99-tailscale.conf
sysctl --system

cat >/etc/systemd/system/tailscale-tweaks.service <<EOF
[Unit]
Description=Tailscale subnet-routing tweaks
After=tailscaled.service network-online.target
Wants=tailscaled.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ethtool -K $${PRIMARY_IF} rx-udp-gro-forwarding on rx-gro-list off

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now tailscale-tweaks.service

echo "=== STAGE 2 DONE: $(date) ==="
echo "Web GUI: https://<tailscale-ip>:8006 (root, realm Linux PAM)"
echo "Не забудь одобрить advertised route в Tailscale admin console:"
echo "  https://login.tailscale.com/admin/machines -> ${hostname} -> Edit route settings"

# Самоотключение — эта стадия больше не должна запускаться на будущих ребутах.
systemctl disable pve-bootstrap-stage2.service
STAGE2EOF

# Подставляем секреты в stage2-скрипт уже на диске (не через переменные
# окружения systemd-юнита — избегаем случайного попадания в `systemctl
# show`/journalctl-дампы конфигурации юнита).
sed -i "s|__ROOT_PASSWORD__|${root_password}|" /usr/local/sbin/pve-bootstrap-stage2.sh
sed -i "s|__TAILSCALE_AUTHKEY__|${tailscale_authkey}|" /usr/local/sbin/pve-bootstrap-stage2.sh
chmod 700 /usr/local/sbin/pve-bootstrap-stage2.sh
chmod 600 /usr/local/sbin/pve-bootstrap-stage2.sh  # содержит root_password/authkey в открытом виде

cat >/etc/systemd/system/pve-bootstrap-stage2.service <<'EOF'
[Unit]
Description=Proxmox bootstrap stage 2 (runs once, after kernel swap reboot)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/pve-bootstrap-stage2.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl enable pve-bootstrap-stage2.service

echo "=== STAGE 1 DONE: $(date) — rebooting into pve kernel ==="
reboot
