# Terraform and Google provider version pins.

terraform {
  required_version = "= 1.16.4"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 8.4.0"
    }
  }
}