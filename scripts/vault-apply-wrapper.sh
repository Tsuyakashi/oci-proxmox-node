# scripts/vault-apply-wrapper.sh
#
# Source из ~/.bashrc (как в iac-proxmox-lab). Перехватывает вызов `terraform`,
# и если текущая директория — это oci-proxmox-node, на ПЕРВЫЙ вызов за сессию
# шелла подтягивает из Vault:
#   - OCI API creds (tenancy/user/fingerprint/private key) -> TF_VAR_*
#   - MinIO backend creds -> подставляются в `terraform init -backend-config=`
#
# Требует: `vault login` уже выполнен (токен в ~/.vault-token или VAULT_TOKEN),
# VAULT_ADDR указывает на Vault (CT 300, bare-pve).

_oci_proxmox_node_vault_loaded=""
_oci_proxmox_node_key_tmp=""

terraform() {
  if [[ "$PWD" == *"oci-proxmox-node"* && -z "$_oci_proxmox_node_vault_loaded" ]]; then
    echo "[vault] fetching oci-proxmox-node secrets..." >&2

    export TF_VAR_tenancy_ocid
    TF_VAR_tenancy_ocid=$(vault kv get -field=tenancy_ocid secret/oci-proxmox-node/api) || return 1
    export TF_VAR_user_ocid
    TF_VAR_user_ocid=$(vault kv get -field=user_ocid secret/oci-proxmox-node/api) || return 1
    export TF_VAR_fingerprint
    TF_VAR_fingerprint=$(vault kv get -field=fingerprint secret/oci-proxmox-node/api) || return 1

    # Приватный ключ хранится в Vault целиком (не путём) — пишем во временный
    # файл 0600, чистим при выходе из шелла, не оставляем на диске дольше сессии.
    _oci_proxmox_node_key_tmp=$(mktemp /tmp/oci_api_key.XXXXXX.pem)
    vault kv get -field=private_key secret/oci-proxmox-node/api > "$_oci_proxmox_node_key_tmp" || return 1
    chmod 600 "$_oci_proxmox_node_key_tmp"
    export TF_VAR_oci_private_key_path="$_oci_proxmox_node_key_tmp"
    trap 'rm -f "$_oci_proxmox_node_key_tmp"' EXIT

    export MINIO_ACCESS_KEY
    MINIO_ACCESS_KEY=$(vault kv get -field=access_key secret/minio/state-backend) || return 1
    export MINIO_SECRET_KEY
    MINIO_SECRET_KEY=$(vault kv get -field=secret_key secret/minio/state-backend) || return 1

    _oci_proxmox_node_vault_loaded=1
  fi

  if [[ "$1" == "init" ]]; then
    command terraform "$@" \
      -backend-config="access_key=$MINIO_ACCESS_KEY" \
      -backend-config="secret_key=$MINIO_SECRET_KEY"
  else
    command terraform "$@"
  fi
}
