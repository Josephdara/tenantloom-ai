# Shared nonprod platform projects and the APIs each one uses.

locals {
  ci_project = "${var.project_prefix}bootstrap"

  projects = {
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
