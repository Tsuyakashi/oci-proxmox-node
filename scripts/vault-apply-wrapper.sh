# scripts/vault-apply-wrapper.sh
#
# Source из ~/.bashrc. Перехватывает вызов `terraform`, и если текущая
# директория — oci-proxmox-node, на ПЕРВЫЙ вызов за сессию шелла тянет
# из Vault (CT 300) ВСЁ, что нужно для apply — ни одного значения через
# terraform.tfvars, файл сознательно не используется вообще:
#   - oci/api    — секреты (tenancy/user/fingerprint/private key)
#   - oci/config — весь остальной конфиг (регион/compartment/AD/образ/
#                  шейп/ресурсы/hostname/ssh-ключ/порты) — не секрет по
#                  природе, но тоже только в Vault, не в файле на диске
#   - proxmox/minio-credentials — MinIO backend creds, общая инфраструктура
#     с iac-proxmox-lab, отдельно заводить не нужно
#
# Требует: `vault login -method=userpass username=<ты>` уже выполнен, и
# твоему логину назначена policy "oci-proxmox-node" (см.
# vault-policy-init.sh) — иначе 403 на oci/api или oci/config.

_oci_proxmox_node_vault_loaded=""
_oci_proxmox_node_key_tmp=""

terraform() {
  if [[ "$PWD" == *"oci-proxmox-node"* && -z "$_oci_proxmox_node_vault_loaded" ]]; then
    echo "[vault] fetching oci-proxmox-node secrets + config..." >&2

    # --- oci/api: секреты ---
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

    export TF_VAR_root_password
    TF_VAR_root_password=$(vault kv get -field=root_password oci/api) || return 1
    export TF_VAR_tailscale_authkey
    TF_VAR_tailscale_authkey=$(vault kv get -field=tailscale_authkey oci/api) || return 1

    # --- oci/config: весь остальной конфиг ---
    export TF_VAR_region
    TF_VAR_region=$(vault kv get -field=region oci/config) || return 1
    export TF_VAR_compartment_ocid
    TF_VAR_compartment_ocid=$(vault kv get -field=compartment_ocid oci/config) || return 1
    export TF_VAR_availability_domain
    TF_VAR_availability_domain=$(vault kv get -field=availability_domain oci/config) || return 1
    export TF_VAR_image_ocid
    TF_VAR_image_ocid=$(vault kv get -field=image_ocid oci/config) || return 1
    export TF_VAR_instance_shape
    TF_VAR_instance_shape=$(vault kv get -field=instance_shape oci/config) || return 1
    export TF_VAR_instance_ocpus
    TF_VAR_instance_ocpus=$(vault kv get -field=instance_ocpus oci/config) || return 1
    export TF_VAR_instance_memory_gb
    TF_VAR_instance_memory_gb=$(vault kv get -field=instance_memory_gb oci/config) || return 1
    export TF_VAR_boot_volume_size_gb
    TF_VAR_boot_volume_size_gb=$(vault kv get -field=boot_volume_size_gb oci/config) || return 1
    export TF_VAR_block_volume_size_gb
    TF_VAR_block_volume_size_gb=$(vault kv get -field=block_volume_size_gb oci/config) || return 1
    export TF_VAR_hostname
    TF_VAR_hostname=$(vault kv get -field=hostname oci/config) || return 1
    export TF_VAR_ssh_public_key
    TF_VAR_ssh_public_key=$(vault kv get -field=ssh_public_key oci/config) || return 1
    export TF_VAR_container_subnet
    TF_VAR_container_subnet=$(vault kv get -field=container_subnet oci/config) || return 1
    export TF_VAR_pve_version_branch
    TF_VAR_pve_version_branch=$(vault kv get -field=pve_version_branch oci/config) || return 1

    # --- Общая инфраструктура (MinIO), тот же путь, что iac-proxmox-lab ---
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
