# Shared names, labels, the API list, and the layers run by infrastructure CI.

locals {
  project_id            = "${var.project_prefix}bootstrap"
  platform_folder_id    = trimprefix(data.google_active_folder.platform.name, "folders/")
  ai_platform_folder_id = trimprefix(data.google_active_folder.ai_platform.name, "folders/")

  labels = {
    component  = "bootstrap"
    env        = "platform"
    managed-by = "terraform"
  }

  # Org-level calls by the provisioning identities are billed to this project.
  apis = toset([
    "accesscontextmanager.googleapis.com",
    "bigquery.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudasset.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudidentity.googleapis.com",
    "cloudquotas.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "orgpolicy.googleapis.com",
    "privilegedaccessmanager.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  state_buckets = {
    platform = "${local.project_id}-platform-state"
    tenant   = "${local.project_id}-tenant-state"
  }
  plan_bucket = "${local.project_id}-saved-plans"
  lock_bucket = "${local.project_id}-apply-lock"

  apply_identities = {
    org      = "sa-org"
    platform = "sa-platform"
    factory  = "sa-factory"
  }
  plan_identities = {
    org      = "sa-plan-org"
    platform = "sa-plan-platform"
    tenant   = "sa-plan-tenant"
  }

  ci_layers = {
    org = {
      dir          = "terraform/org"
      plan         = "org"
      apply        = "org"
      state_bucket = "platform"
      state_prefix = "org"
    }
    platform = {
      dir          = "terraform/platform"
      plan         = "platform"
      apply        = "platform"
      state_bucket = "platform"
      state_prefix = "platform"
    }
  }
}
