output "access_policy" {
  value = google_access_context_manager_access_policy.this.name
}

output "prod_perimeter" {
  value = google_access_context_manager_service_perimeter.prod.name
}
