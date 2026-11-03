locals {
  apis = {
    sandbox = [
      "aiplatform.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "iam.googleapis.com",
      "logging.googleapis.com",
      "modelarmor.googleapis.com",
      "serviceusage.googleapis.com",
    ]
    prod = [
      "aiplatform.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "iam.googleapis.com",
      "logging.googleapis.com",
      "modelarmor.googleapis.com",
      "serviceusage.googleapis.com",
    ]
    nonprod = [
      "accesscontextmanager.googleapis.com",
      "aiplatform.googleapis.com",
      "bigquery.googleapis.com",
      "billingbudgets.googleapis.com",
      "cloudbilling.googleapis.com",
      "cloudbuild.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "logging.googleapis.com",
      "modelarmor.googleapis.com",
      "monitoring.googleapis.com",
      "orgpolicy.googleapis.com",
      "secretmanager.googleapis.com",
      "serviceusage.googleapis.com",
      "storage.googleapis.com",
    ]
  }

  project_apis = merge([
    for env, apis in local.apis : { for api in apis : "${env}/${api}" => { env = env, api = api } }
  ]...)
}

# Sandbox, nonprod, and prod projects under the ai-platform folder.
resource "google_project" "env" {
  for_each = toset(keys(local.apis))

  project_id          = "${var.project_prefix}${each.key}"
  name                = "${var.project_prefix}${each.key}"
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "PREVENT"
  labels              = merge(var.labels, { env = each.key })
}

# APIs each project needs.
resource "google_project_service" "enabled" {
  for_each = local.project_apis

  project            = google_project.env[each.value.env].project_id
  service            = each.value.api
  disable_on_destroy = false
}
