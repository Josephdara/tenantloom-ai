# Data Access audit logs on the ai-platform folder. IAM logs record service account token requests.

resource "google_folder_iam_audit_config" "ai_platform" {
  for_each = toset(["aiplatform.googleapis.com", "iam.googleapis.com"])
  folder   = google_folder.ai_platform.name
  service  = each.key

  dynamic "audit_log_config" {
    for_each = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
    content {
      log_type = audit_log_config.value
    }
  }
}
