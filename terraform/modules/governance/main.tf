locals {
  data_access_services = toset([
    "aiplatform.googleapis.com",
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ])
  data_access_log_types = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
}

# Data Access audit logs for each listed service, inherited by every project in the folder.
resource "google_folder_iam_audit_config" "data_access" {
  for_each = local.data_access_services

  folder  = var.folder
  service = each.value

  dynamic "audit_log_config" {
    for_each = local.data_access_log_types
    content {
      log_type = audit_log_config.value
    }
  }
}
