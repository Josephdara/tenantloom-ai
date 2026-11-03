output "service_account" {
  value = google_service_account.probe.email
}

output "cloud_run_agent" {
  value = google_project_service_identity.run.member
}
