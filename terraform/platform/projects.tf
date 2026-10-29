# Shared nonprod platform projects and the APIs each one uses. The lab footprint hosts the eval and kms
# roles in the ops project.

locals {
  ci_project = "${var.project_prefix}bootstrap"

  role_apis = {
    ops = [
      "aiplatform.googleapis.com",
      "artifactregistry.googleapis.com",
      "bigquery.googleapis.com",
      "cloudbuild.googleapis.com",
      "clouddeploy.googleapis.com",
      "iam.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
    ]
    eval = [
      "aiplatform.googleapis.com",
      "bigquery.googleapis.com",
      "iam.googleapis.com",
      "logging.googleapis.com",
      "run.googleapis.com",
      "storage.googleapis.com",
    ]
    kms = [
      "cloudkms.googleapis.com",
      "logging.googleapis.com",
    ]
  }

  host = { for role in keys(local.role_apis) : role => var.footprint == "lab" ? "ops" : role }

  projects = {
    for h in distinct(values(local.host)) :
    h => sort(distinct(flatten([for role, hosted_in in local.host : local.role_apis[role] if hosted_in == h])))
  }

  project_services = merge([
    for p, apis in local.projects : { for api in apis : "${p}/${api}" => { project = p, service = api } }
  ]...)
}

resource "google_project" "shared" {
  for_each            = local.projects
  name                = "${var.project_prefix}${each.key}"
  project_id          = "${var.project_prefix}${each.key}"
  folder_id           = var.platform_folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "PREVENT"

  labels = {
    component  = each.key
    env        = "platform"
    managed-by = "terraform"
  }
}

resource "google_project_service" "shared" {
  for_each           = local.project_services
  project            = google_project.shared[each.value.project].project_id
  service            = each.value.service
  disable_on_destroy = false
}
