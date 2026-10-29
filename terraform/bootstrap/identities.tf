# Apply and read-only plan service accounts for each provisioning layer.

resource "google_service_account" "apply" {
  for_each     = local.apply_identities
  project      = google_project.bootstrap.project_id
  account_id   = each.value
  display_name = "Apply identity: ${each.key} layer"

  depends_on = [google_project_service.enabled]
}

resource "google_service_account" "plan" {
  for_each     = local.plan_identities
  project      = google_project.bootstrap.project_id
  account_id   = each.value
  display_name = "Read-only plan identity: ${each.key} layer"

  depends_on = [google_project_service.enabled]
}
