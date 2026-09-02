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
vault policy write oci-proxmox-node - <<POLICY
path "oci/data/api" {
  capabilities = ["create", "read", "update"]
}
path "oci/metadata/api" {
  capabilities = ["read", "list"]
}
POLICY

echo "Policy 'oci-proxmox-node' готова (mount oci/, путь oci/api)."
echo ""
echo "Привязать к своему userpass-логину (добавить policy, не заменить —"
echo "через запятую перечисли все policies, которые уже были у юзера):"
echo "  vault write auth/userpass/users/<ты> \\"
echo "    token_policies=\"operator-manual-apply,oci-proxmox-node\""
echo ""
echo "Дальше засеять сам секрет (после vault login, если сессия истекла):"
echo "  vault kv put oci/api \\"
echo "    tenancy_ocid=\"...\" user_ocid=\"...\" fingerprint=\"...\" \\"
echo "    private_key=@/home/tsu/.oci/oci_api_key.pem"
