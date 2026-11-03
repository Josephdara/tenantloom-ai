locals {
  prod             = var.project_ids["prod"]
  prod_app_filter  = "resource.type=(\"cloud_run_revision\" OR \"cloud_run_job\") AND NOT logName:\"cloudaudit.googleapis.com\""
  prod_log_buckets = { app-logs = 90, model-armor = 30 }
  prod_log_filters = { app-logs = local.prod_app_filter, model-armor = local.model_armor_filter }
}

# Prod key ring for customer-managed encryption keys.
resource "google_kms_key_ring" "prod" {
  project  = local.prod
  name     = "platform"
  location = var.region
}

# Key that encrypts prod log buckets, rotated every 90 days.
resource "google_kms_crypto_key" "logs" {
  name            = "logs"
  key_ring        = google_kms_key_ring.prod.id
  rotation_period = "7776000s"
  labels          = merge(var.labels, { env = "prod", purpose = "log-encryption" })

  lifecycle {
    prevent_destroy = true
  }
}

# Reading the project's logging settings returns, and if needed creates, the account Logging uses for CMEK.
data "google_logging_project_settings" "prod" {
  project = local.prod
}

# Lets only the prod Logging service account use the log key.
resource "google_kms_crypto_key_iam_member" "logs" {
  crypto_key_id = google_kms_crypto_key.logs.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_logging_project_settings.prod.kms_service_account_id}"
}

# CMEK log buckets for prod application logs and Model Armor logs.
resource "google_logging_project_bucket_config" "prod" {
  for_each = local.prod_log_buckets

  project        = local.prod
  location       = var.region
  bucket_id      = each.key
  retention_days = each.value

  cmek_settings {
    kms_key_name = google_kms_crypto_key.logs.id
  }

  depends_on = [google_kms_crypto_key_iam_member.logs]
}

# Routes prod Cloud Run and Model Armor logs to their CMEK buckets.
resource "google_logging_project_sink" "prod" {
  for_each = local.prod_log_filters

  project                = local.prod
  name                   = each.key
  destination            = "logging.googleapis.com/${google_logging_project_bucket_config.prod[each.key].id}"
  filter                 = each.value
  unique_writer_identity = true
}

# Keeps the same logs out of the prod default bucket, which is not CMEK-encrypted.
resource "google_logging_project_exclusion" "prod" {
  for_each = local.prod_log_filters

  project = local.prod
  name    = each.key
  filter  = each.value
}

# Lets auditors read prod Model Armor logs.
resource "google_logging_log_view_iam_member" "prod_model_armor_reader" {
  parent   = "projects/${local.prod}"
  location = var.region
  bucket   = google_logging_project_bucket_config.prod["model-armor"].bucket_id
  name     = "_AllLogs"
  role     = "roles/logging.viewAccessor"
  member   = "group:${var.auditors_group}"
}
