terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }

  # Тот же self-hosted MinIO (S3-совместимый), что и у iac-proxmox-lab,
  # но ОТДЕЛЬНЫЙ bucket/key — стейты не пересекаются.
  backend "s3" {
    bucket                      = "oci-proxmox-node"
    key                         = "terraform.tfstate"
    region                      = "us-east-1" # фиктивный, MinIO не проверяет
    endpoint                    = "http://192.168.100.100:9000"
    access_key                  = "" # передать через -backend-config или env AWS_ACCESS_KEY_ID
    secret_key                  = "" # передать через -backend-config или env AWS_SECRET_ACCESS_KEY
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.oci_private_key_path
  region           = var.region
}
