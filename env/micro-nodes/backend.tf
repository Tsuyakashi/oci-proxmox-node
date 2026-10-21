terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }

  # Тот же MinIO-бакет, что у env/pve-node, но свой key — стейты
  # независимы: destroy/replace A1-ноды не задевает micro-ноды и наоборот.
  # access_key/secret_key — через tf-secrets (minio/credentials).
  backend "s3" {
    bucket                      = "oci-proxmox-node"
    key                         = "micro-nodes/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    use_path_style              = true
  }
}
