# IDs and names used by the other layers.

output "project_id" {
  value = google_project.bootstrap.project_id
}

output "project_number" {
  value = google_project.bootstrap.number
}

output "platform_folder_id" {
  value = google_folder.platform.folder_id
}

output "ai_platform_folder_id" {
  value = google_folder.ai_platform.folder_id
}

output "state_buckets" {
  value = local.state_buckets
}

output "plan_bucket" {
  value = local.plan_bucket
}

output "lock_bucket" {
  value = local.lock_bucket
}

output "apply_identities" {
  value = { for k, sa in google_service_account.apply : k => sa.email }
}

output "plan_identities" {
  value = { for k, sa in google_service_account.plan : k => sa.email }
}
