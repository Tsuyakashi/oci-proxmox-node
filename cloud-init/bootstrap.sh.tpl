#!/bin/bash
# Bootstrap Proxmox VE поверх чистого Debian 12 (bookworm) образа OCI.
#
# ВАЖНО: официально PVE ставится только поверх Debian, не Ubuntu.
# Убедись, что image_ocid в terraform.tfvars указывает на Debian 12
# (aarch64 для Ampere A1 / amd64 для x86-шейпов), иначе шаг с
# apt install proxmox-ve упадёт на конфликте ядер/пакетов.

set -euxo pipefail

exec > >(tee /var/log/pve-bootstrap.log) 2>&1

hostnamectl set-hostname "${hostname}"
echo "127.0.1.1 ${hostname}.local ${hostname}" >> /etc/hosts

apt-get update
apt-get install -y curl gnupg2 ca-certificates

# --- Репозиторий Proxmox VE (no-subscription) ---
echo "deb [signed-by=/usr/share/keyrings/proxmox-release-${pve_version_branch}.gpg] http://download.proxmox.com/debian/pve ${pve_version_branch} pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-install-repo.list

curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-${pve_version_branch}.gpg \
  -o /usr/share/keyrings/proxmox-release-${pve_version_branch}.gpg

apt-get update

# resolv.conf/DNS иногда перетирается на облачных образах при следующем apt update —
# фиксируем nameserver'ы явно, как уже делалось в iac-proxmox-lab (proxmox-init.sh)
cat <<'EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Ядро Proxmox + сам PVE. DEBIAN_FRONTEND=noninteractive чтобы cloud-init
# не завис на диалоге postfix/grub.
export DEBIAN_FRONTEND=noninteractive
apt-get install -y proxmox-default-kernel
apt-get install -y proxmox-ve postfix open-iscsi chrony

# Убираем стоковое ядро облачного провайдера в пользу pve-kernel при следующей загрузке —
# без него PVE поднимется, но без ZFS/некоторых модулей.
# (оставляем закомментированным — раскомментировать после проверки, что pve-kernel
# нормально грузится на этом OCI-шейпе; безопаснее сначала перезагрузиться руками)
# apt-get remove -y linux-image-cloud-arm64 linux-headers-cloud-arm64 || true

# qemu-guest-agent тут не нужен — это не гость, а сам гипервизор

# --- Сетевой мост vmbr0 поверх единственного облачного интерфейса ---
# OCI отдаёт один NIC (обычно ens3/enp0s3). Подхватываем его имя автоматически.
PRIMARY_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
PRIMARY_IP=$(ip -4 addr show "$PRIMARY_IF" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+')
GATEWAY=$(ip route | awk '/default/ {print $3}')

cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

iface $PRIMARY_IF inet manual

auto vmbr0
iface vmbr0 inet static
    address $PRIMARY_IP
    gateway $GATEWAY
    bridge-ports $PRIMARY_IF
    bridge-stp off
    bridge-fd 0
EOF

echo "Bootstrap done, rebooting to apply network + kernel changes" >> /var/log/pve-bootstrap.log
reboot
