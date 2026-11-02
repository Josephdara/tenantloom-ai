# Consumers create resources that need these APIs, so the IDs are released only once the APIs are enabled.
output "project_ids" {
  value      = { for env, p in google_project.env : env => p.project_id }
  depends_on = [google_project_service.enabled]
}

output "project_numbers" {
  value      = { for env, p in google_project.env : env => p.number }
  depends_on = [google_project_service.enabled]
}
