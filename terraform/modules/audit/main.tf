locals {
  nonprod                 = var.project_ids["nonprod"]
  model_armor_filter      = "logName:\"modelarmor.googleapis.com\""
  model_armor_sources     = toset(["sandbox", "nonprod"])
  model_armor_destination = "logging.googleapis.com/${google_logging_project_bucket_config.model_armor.id}"
  watched_groups          = [var.governance_group, var.auditors_group]
}

# Audit logs from every project in the folder, kept for one year.
resource "google_bigquery_dataset" "audit" {
  project                         = local.nonprod
  dataset_id                      = "audit_logs"
  location                        = var.region
  default_partition_expiration_ms = 31536000000
  delete_contents_on_destroy      = false
  labels                          = merge(var.labels, { env = "nonprod", purpose = "audit-logs" })
}

# Routes Admin Activity and Data Access audit logs from the folder and its projects to the audit dataset.
resource "google_logging_folder_sink" "audit" {
  name             = "platform-audit"
  folder           = var.folder
  include_children = true
  destination      = "bigquery.googleapis.com/projects/${local.nonprod}/datasets/${google_bigquery_dataset.audit.dataset_id}"
  filter           = "logName:\"cloudaudit.googleapis.com\""

  bigquery_options {
    use_partitioned_tables = true
  }
}

# Lets the folder sink write audit tables.
resource "google_bigquery_dataset_iam_member" "audit_sink_writer" {
  project    = local.nonprod
  dataset_id = google_bigquery_dataset.audit.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_folder_sink.audit.writer_identity
}

# Lets auditors read the audit tables.
resource "google_bigquery_dataset_iam_member" "audit_reader" {
  project    = local.nonprod
  dataset_id = google_bigquery_dataset.audit.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "group:${var.auditors_group}"
}

# Lets auditors run queries against the audit dataset.
resource "google_project_iam_member" "auditor_job_user" {
  project = local.nonprod
  role    = "roles/bigquery.jobUser"
  member  = "group:${var.auditors_group}"
}

# Restricted bucket for Model Armor prompt and response screening logs.
resource "google_logging_project_bucket_config" "model_armor" {
  project        = local.nonprod
  location       = var.region
  bucket_id      = "model-armor"
  retention_days = 30
  description    = "Model Armor screening logs from sandbox and nonprod"
}

# Routes each project's Model Armor logs to the restricted bucket.
resource "google_logging_project_sink" "model_armor" {
  for_each = local.model_armor_sources

  project                = var.project_ids[each.key]
  name                   = "model-armor"
  destination            = local.model_armor_destination
  filter                 = local.model_armor_filter
  unique_writer_identity = true
}

# Lets the sandbox sink write into the nonprod bucket.
resource "google_project_iam_member" "model_armor_sink_writer" {
  project = local.nonprod
  role    = "roles/logging.bucketWriter"
  member  = google_logging_project_sink.model_armor["sandbox"].writer_identity
}

# Logs Writer for every sink that writes into nonprod from another resource, as Cloud Logging requires for all destinations.
resource "google_project_iam_member" "cross_project_sink_log_writer" {
  for_each = {
    folder-audit        = google_logging_folder_sink.audit.writer_identity
    sandbox-model-armor = google_logging_project_sink.model_armor["sandbox"].writer_identity
    org-identity-audit  = "serviceAccount:service-org-${var.org_id}@gcp-sa-logging.iam.gserviceaccount.com"
  }

  project = local.nonprod
  role    = "roles/logging.logWriter"
  member  = each.value
}

# Keeps Model Armor logs out of the default bucket, where wider audiences can read them.
resource "google_logging_project_exclusion" "model_armor" {
  for_each = local.model_armor_sources

  project = var.project_ids[each.key]
  name    = "model-armor"
  filter  = local.model_armor_filter
}

# Lets auditors read the Model Armor bucket.
resource "google_logging_log_view_iam_member" "model_armor_reader" {
  parent   = "projects/${local.nonprod}"
  location = var.region
  bucket   = google_logging_project_bucket_config.model_armor.bucket_id
  name     = "_AllLogs"
  role     = "roles/logging.viewAccessor"
  member   = "group:${var.auditors_group}"
}

# Receives Cloud Identity admin audit logs from the organization sink created outside Terraform.
resource "google_logging_project_bucket_config" "identity_audit" {
  project        = local.nonprod
  location       = var.region
  bucket_id      = "identity-audit"
  retention_days = 365
  description    = "Cloud Identity admin audit logs routed by an organization sink"
}

# Counts membership changes to the approver and auditor groups.
resource "google_logging_metric" "watched_group_changes" {
  project     = local.nonprod
  name        = "watched-group-membership-changes"
  description = "Membership changes to ai-governance and auditors"
  bucket_name = google_logging_project_bucket_config.identity_audit.id
  filter      = "protoPayload.serviceName=\"admin.googleapis.com\" AND protoPayload.methodName:\"GroupMember\" AND (${join(" OR ", [for g in local.watched_groups : "\"${g}\""])})"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Email channel for governance alerts.
resource "google_monitoring_notification_channel" "governance" {
  project      = local.nonprod
  display_name = "Governance alerts"
  type         = "email"
  user_labels  = var.labels

  labels = {
    email_address = var.governance_group
  }
}

# Alerts governance on any membership change to the approver or auditor groups.
resource "google_monitoring_alert_policy" "watched_group_changes" {
  project               = local.nonprod
  display_name          = "Approver or auditor group membership changed"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.governance.id]

  conditions {
    display_name = "Membership change logged"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.watched_group_changes.name}\" AND resource.type=\"logging_bucket\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
}
