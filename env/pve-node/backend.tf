terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }

  # Self-hosted MinIO (тот же инстанс, что у iac-proxmox-lab), но
  # ОТДЕЛЬНЫЙ bucket — стейты не пересекаются.
  # access_key/secret_key НЕ заданы тут намеренно — приходят через
  # `terraform init -backend-config=...` из scripts/vault-apply-wrapper.sh,
  # который берёт их из proxmox/minio-credentials — того же Vault-пути,
  # что уже использует iac-proxmox-lab, ничего нового заводить не нужно.
  #
  # endpoints.s3 / use_path_style — актуальный синтаксис (не
  # endpoint/force_path_style, они deprecated), тот же, что уже стоит во
  # всех backend.tf в iac-proxmox-lab.
  backend "s3" {
    bucket                      = "oci-proxmox-node"
    key                         = "pve-node/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "http://192.168.100.100:9000" }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    use_path_style              = true
  }
}
