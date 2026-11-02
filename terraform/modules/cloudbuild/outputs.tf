output "connection" {
  value = try(google_cloudbuildv2_connection.github["platform"].id, null)
}
