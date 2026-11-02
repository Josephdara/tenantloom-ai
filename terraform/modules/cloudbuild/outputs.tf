output "connection" {
  value = google_cloudbuildv2_connection.github.id
}

output "connection_action_uri" {
  value = try(google_cloudbuildv2_connection.github.installation_state[0].action_uri, null)
}
