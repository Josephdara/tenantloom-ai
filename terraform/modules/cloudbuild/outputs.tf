output "connection" {
  value = try(google_cloudbuildv2_connection.github["platform"].id, null)
}

output "platform_repository_link" {
  value = try(google_cloudbuildv2_repository.platform["platform"].id, null)
}

output "platform_repository" {
  value = google_artifact_registry_repository.platform.id
}
