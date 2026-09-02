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
  # `terraform init -backend-config=...` из scripts/vault-apply-wrapper.sh
  backend "s3" {
    bucket                      = "oci-proxmox-node"
    key                         = "terraform.tfstate"
    region                      = "us-east-1" # фиктивный, MinIO не проверяет
    endpoint                    = "http://192.168.100.100:9000"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
