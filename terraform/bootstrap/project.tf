# The bootstrap project and the APIs enabled in it.

resource "google_project" "bootstrap" {
  name                = local.project_id
  project_id          = local.project_id
  folder_id           = local.platform_folder_id
  billing_account     = var.billing_account
  labels              = local.labels
  auto_create_network = false
  deletion_policy     = "PREVENT"
}

resource "google_project_service" "enabled" {
  for_each           = local.apis
  project            = google_project.bootstrap.project_id
  service            = each.value
  disable_on_destroy = false
}
