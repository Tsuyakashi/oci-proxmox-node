# scripts/vault-apply-wrapper.sh
#
# Source из ~/.bashrc. Перехватывает вызов `terraform`, и если текущая
# директория — oci-proxmox-node, на ПЕРВЫЙ вызов за сессию шелла тянет
# из Vault (CT 300):
#   - OCI API creds (tenancy/user/fingerprint/private key) — oci/api,
#     отдельный KV-v2 mount под этот проект (см. vault-policy-init.sh),
#     НЕ mount "proxmox/" из iac-proxmox-lab
#   - MinIO backend creds — proxmox/minio-credentials (уже существует,
#     заведён iac-proxmox-lab; это общая инфраструктура — тот же MinIO
#     обслуживает оба проекта, — переиспользуется как есть)
#
# Требует: `vault login -method=userpass username=<ты>` уже выполнен, и
# твоему логину назначена policy "oci-proxmox-node" (см.
# vault-policy-init.sh) — иначе 403 на oci/api.

_oci_proxmox_node_vault_loaded=""
_oci_proxmox_node_key_tmp=""

terraform() {
  if [[ "$PWD" == *"oci-proxmox-node"* && -z "$_oci_proxmox_node_vault_loaded" ]]; then
    echo "[vault] fetching oci-proxmox-node secrets..." >&2

    export TF_VAR_tenancy_ocid
    TF_VAR_tenancy_ocid=$(vault kv get -field=tenancy_ocid oci/api) || return 1
    export TF_VAR_user_ocid
    TF_VAR_user_ocid=$(vault kv get -field=user_ocid oci/api) || return 1
    export TF_VAR_fingerprint
    TF_VAR_fingerprint=$(vault kv get -field=fingerprint oci/api) || return 1

    # Приватный ключ хранится в Vault целиком (не путём) — пишем во временный
    # файл 0600, чистим при выходе из шелла, не оставляем на диске дольше сессии.
    _oci_proxmox_node_key_tmp=$(mktemp /tmp/oci_api_key.XXXXXX.pem)
    vault kv get -field=private_key oci/api > "$_oci_proxmox_node_key_tmp" || return 1
    chmod 600 "$_oci_proxmox_node_key_tmp"
    export TF_VAR_oci_private_key_path="$_oci_proxmox_node_key_tmp"
    trap 'rm -f "$_oci_proxmox_node_key_tmp"' EXIT

    # Общая инфраструктура (MinIO), не относится к mount'у oci/ — тот же
    # путь, что уже использует iac-proxmox-lab.
    export AWS_ACCESS_KEY_ID
    AWS_ACCESS_KEY_ID=$(vault kv get -field=access_key proxmox/minio-credentials) || return 1
    export AWS_SECRET_ACCESS_KEY
    AWS_SECRET_ACCESS_KEY=$(vault kv get -field=secret_key proxmox/minio-credentials) || return 1

    _oci_proxmox_node_vault_loaded=1
  fi

  if [[ "$1" == "init" ]]; then
    command terraform "$@" \
      -backend-config="access_key=$AWS_ACCESS_KEY_ID" \
      -backend-config="secret_key=$AWS_SECRET_ACCESS_KEY"
  else
    command terraform "$@"
  fi
}
