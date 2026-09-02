#!/bin/bash
#
# scripts/vault-policy-init.sh
#
# Расширяет уже существующую policy `operator-manual-apply` (заведена
# vault-userpass-init.sh в iac-proxmox-lab) доступом к новому пути
# proxmox/oci-api — не создаёт отдельный mount/policy под oci-proxmox-node,
# т.к. это тот же самый Vault (CT 300), уже используемый iac-proxmox-lab,
# с единым KV-v2 mount "proxmox/".
#
# ВАЖНО: `vault policy write` перезаписывает документ policy целиком —
# ниже воспроизведены пути, известные на момент написания этого скрипта
# (terraform-provider/minio-credentials/ssh-keys из iac-proxmox-lab) плюс
# новый oci-api. Если operator-manual-apply с тех пор обзавелась ещё
# какими-то path-блоками вручную — добавь их сюда же перед запуском,
# иначе они потеряются при перезаписи.
#
# oci-api получает create+update (не только read) — в отличие от
# остальных путей здесь, этот секрет операторы сеют сами через
# `vault kv put`, не root/CI единоразово.
#
# Запуск:
#   VAULT_ADDR=http://192.168.100.200:8200 ./scripts/vault-policy-init.sh

set -e
: "${VAULT_ADDR:?set VAULT_ADDR before running (e.g. http://192.168.100.200:8200)}"

vault policy write operator-manual-apply - <<EOF
path "proxmox/data/terraform-provider" {
  capabilities = ["read"]
}
path "proxmox/data/minio-credentials" {
  capabilities = ["read"]
}
path "proxmox/data/ssh-keys" {
  capabilities = ["read"]
}
path "proxmox/data/oci-api" {
  capabilities = ["create", "read", "update"]
}
path "proxmox/metadata/oci-api" {
  capabilities = ["read", "list"]
}
EOF

echo "operator-manual-apply policy обновлена — добавлен доступ к proxmox/oci-api."
echo "Проверить: vault token capabilities proxmox/data/oci-api"
echo ""
echo "Дальше сеять сам секрет можно под тем же логином, которым обычно"
echo "делаешь terraform apply (userpass, не root):"
echo "  vault login -method=userpass username=<ты>"
echo "  vault kv put proxmox/oci-api \\"
echo "    tenancy_ocid=\"...\" user_ocid=\"...\" fingerprint=\"...\" \\"
echo "    private_key=@/home/tsu/.oci/oci_api_key.pem"
