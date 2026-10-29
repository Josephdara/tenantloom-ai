# Organization access policy and the dry-run perimeter for tenant test projects.

locals {
  restricted_services = [
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "binaryauthorization.googleapis.com",
    "modelarmor.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
  ]

  provisioning_identities = [
    for name in ["sa-factory", "sa-platform", "sa-plan-tenant", "sa-plan-platform"] :
    "serviceAccount:${name}@${local.ci_project}.iam.gserviceaccount.com"
  ]

  test_perimeter_projects = []
}

resource "google_access_context_manager_access_policy" "org" {
  parent = "organizations/${var.org_id}"
  title  = "tenantloom-ai"
}

resource "google_access_context_manager_service_perimeter" "test" {
  parent                    = "accessPolicies/${google_access_context_manager_access_policy.org.name}"
  name                      = "accessPolicies/${google_access_context_manager_access_policy.org.name}/servicePerimeters/test"
  title                     = "test"
  perimeter_type            = "PERIMETER_TYPE_REGULAR"
  use_explicit_dry_run_spec = true

  spec {
    resources           = local.test_perimeter_projects
    restricted_services = local.restricted_services

    ingress_policies {
      title = "provisioning"

      ingress_from {
        identities = local.provisioning_identities

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
  }
}
