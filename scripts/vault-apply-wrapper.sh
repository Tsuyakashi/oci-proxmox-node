# scripts/vault-apply-wrapper.sh
#
# Source из ~/.bashrc (тот же паттерн, что vault-apply-wrapper.sh в
# iac-proxmox-lab). Перехватывает вызов `terraform`, и если текущая
# директория — oci-proxmox-node, на ПЕРВЫЙ вызов за сессию шелла тянет
# из Vault (тот же CT 300 / mount "proxmox/", что уже используется
# iac-proxmox-lab — НЕ отдельный mount под этот проект):
#   - OCI API creds (tenancy/user/fingerprint/private key) — proxmox/oci-api
#   - MinIO backend creds — proxmox/minio-credentials (уже существует,
#     заведён iac-proxmox-lab; здесь просто переиспользуется)
#
# Требует: `vault login -method=userpass username=<ты>` уже выполнен,
# и scripts/vault-policy-init.sh уже прогнан (иначе 403 на proxmox/oci-api
# — capability check возвращает "please ensure client's policies grant
# access to path ...").

_oci_proxmox_node_vault_loaded=""
_oci_proxmox_node_key_tmp=""

terraform() {
  if [[ "$PWD" == *"oci-proxmox-node"* && -z "$_oci_proxmox_node_vault_loaded" ]]; then
    echo "[vault] fetching oci-proxmox-node secrets..." >&2

    export TF_VAR_tenancy_ocid
    TF_VAR_tenancy_ocid=$(vault kv get -field=tenancy_ocid proxmox/oci-api) || return 1
    export TF_VAR_user_ocid
    TF_VAR_user_ocid=$(vault kv get -field=user_ocid proxmox/oci-api) || return 1
    export TF_VAR_fingerprint
    TF_VAR_fingerprint=$(vault kv get -field=fingerprint proxmox/oci-api) || return 1

    # Приватный ключ хранится в Vault целиком (не путём) — пишем во временный
    # файл 0600, чистим при выходе из шелла, не оставляем на диске дольше сессии.
    _oci_proxmox_node_key_tmp=$(mktemp /tmp/oci_api_key.XXXXXX.pem)
    vault kv get -field=private_key proxmox/oci-api > "$_oci_proxmox_node_key_tmp" || return 1
    chmod 600 "$_oci_proxmox_node_key_tmp"
    export TF_VAR_oci_private_key_path="$_oci_proxmox_node_key_tmp"
    trap 'rm -f "$_oci_proxmox_node_key_tmp"' EXIT

    # Тот же путь, что уже использует iac-proxmox-lab — не заводим новый.
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
