#!/bin/bash
#
# scripts/vault-policy-init.sh
#
# Отдельный KV-v2 mount "oci/" (не "proxmox/") + отдельная policy
# "oci-proxmox-node" под этот проект — сознательно не завязано на mount
# iac-proxmox-lab, чтобы секреты этого репо не жили вперемешку с чужими
# (Proxmox API token, SSH-ключи и т.д.) под одним policy-документом.
# MinIO backend-креды по-прежнему читаются из существующего
# proxmox/minio-credentials (см. vault-apply-wrapper.sh) — это separate
# concern, инфраструктурный секрет, а не то, что этот скрипт заводит.
#
# Запуск (один раз):
#   VAULT_ADDR=http://192.168.100.200:8200 ./scripts/vault-policy-init.sh

set -e
: "${VAULT_ADDR:?set VAULT_ADDR before running (e.g. http://192.168.100.200:8200)}"

# 1. Отдельный секрет-движок под этот проект, если ещё не включён.
if ! vault secrets list -format=json | grep -q '"oci/"'; then
    echo "Включаю KV-v2 mount 'oci/'..."
    vault secrets enable -path=oci -version=2 kv
else
    echo "Mount 'oci/' уже существует, пропускаю."
fi

# 2. Policy, изолированная от всего, что использует iac-proxmox-lab.
#    Два пути в mount'е oci/: api (секреты) и config (весь остальной
#    конфиг — регион/шейп/сеть/ssh-ключ) — оба одинаково create/read/update,
#    т.к. оператор сеет и правит их сам, не через root/CI единоразово.
vault policy write oci-proxmox-node - <<POLICY
path "oci/data/api" {
  capabilities = ["create", "read", "update"]
}
path "oci/metadata/api" {
  capabilities = ["read", "list"]
}
path "oci/data/config" {
  capabilities = ["create", "read", "update"]
}
path "oci/metadata/config" {
  capabilities = ["read", "list"]
}
POLICY

echo "Policy 'oci-proxmox-node' готова (mount oci/, пути oci/api и oci/config)."
echo ""
echo "Привязать к своему userpass-логину (добавить policy, не заменить —"
echo "через запятую перечисли все policies, которые уже были у юзера):"
echo "  vault write auth/userpass/users/<ты> \\"
echo "    token_policies=\"operator-manual-apply,oci-proxmox-node\""
echo ""
echo "Дальше засеять секреты (после vault login, если сессия истекла)."
echo "root_password — пароль для веб-GUI Proxmox (root, realm Linux PAM);"
echo "tailscale_authkey — Settings -> Keys в консоли Tailscale (reusable,"
echo "с разумным TTL — даёт unattended 'tailscale up' без ручного логина):"
echo "  vault kv put oci/api \\"
echo "    tenancy_ocid=\"...\" user_ocid=\"...\" fingerprint=\"...\" \\"
echo "    private_key=@/home/tsu/.oci/oci_api_key.pem \\"
echo "    root_password=\"...\" \\"
echo "    tailscale_authkey=\"tskey-auth-...\""
echo ""
echo "И весь остальной конфиг (не секрет, но тоже теперь только в Vault,"
echo "никакого terraform.tfvars). image_ocid — результат"
echo "scripts/import-debian-image.py (разовый шаг вне Terraform, см. README):"
echo "  vault kv put oci/config \\"
echo "    region=\"eu-frankfurt-1\" \\"
echo "    compartment_ocid=\"...\" \\"
echo "    availability_domain=\"...\" \\"
echo "    image_ocid=\"<из import-debian-image.py>\" \\"
echo "    instance_shape=\"VM.Standard.A1.Flex\" \\"
echo "    instance_ocpus=\"2\" \\"
echo "    instance_memory_gb=\"12\" \\"
echo "    boot_volume_size_gb=\"60\" \\"
echo "    block_volume_size_gb=\"140\" \\"
echo "    hostname=\"oci-pve\" \\"
echo "    ssh_public_key=\"\$(cat ~/.ssh/id_ed25519.pub)\" \\"
echo "    container_subnet=\"10.10.10.0/24\" \\"
echo "    pve_version_branch=\"trixie\""
