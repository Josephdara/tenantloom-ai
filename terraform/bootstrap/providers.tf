# Google provider settings, with an optional quota project.

provider "google" {
  region = var.region

  user_project_override = var.quota_project != null
  billing_project       = var.quota_project
}
