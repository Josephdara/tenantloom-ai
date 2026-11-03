locals {
  restricted_services = [
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
  ]

  management_identities = [
    "serviceAccount:${var.terraform_service_account}",
    "serviceAccount:${var.terraform_plan_service_account}",
    "user:${var.breakglass_account}",
  ]
}

# Prod perimeter in dry run: violations are logged but nothing is blocked until enforcement.
resource "google_access_context_manager_service_perimeter" "prod" {
  parent                    = "accessPolicies/${google_access_context_manager_access_policy.this.name}"
  name                      = "accessPolicies/${google_access_context_manager_access_policy.this.name}/servicePerimeters/prod"
  title                     = "prod"
  perimeter_type            = "PERIMETER_TYPE_REGULAR"
  use_explicit_dry_run_spec = true

  spec {
    resources           = ["projects/${var.prod_project_number}"]
    restricted_services = local.restricted_services

    vpc_accessible_services {
      enable_restriction = true
      allowed_services   = ["RESTRICTED-SERVICES"]
    }

    ingress_policies {
      title = "terraform-and-break-glass"

      ingress_from {
        identities = local.management_identities
        sources {
          access_level = "*"
        }
      }

      ingress_to {
        resources = ["*"]
        operations {
          service_name = "*"
        }
      }
    }

    ingress_policies {
      title = "platform-admins"

      ingress_from {
        identities = ["group:${var.platform_admins_group}"]
        sources {
          access_level = "*"
        }
      }

      ingress_to {
        resources = ["*"]
        operations {
          service_name = "*"
        }
      }
    }

    egress_policies {
      title = "audit-sink"

      egress_from {
        identities = [var.audit_sink_writer]
      }

      egress_to {
        resources = ["projects/${var.nonprod_project_number}"]
        operations {
          service_name = "bigquery.googleapis.com"
          method_selectors {
            method = "*"
          }
        }
      }
    }
  }
}
