# Dataset and table for CI apply records, kept for 365 days.

resource "google_bigquery_dataset" "ci_records" {
  dataset_id                      = "ci_records"
  project                         = google_project.bootstrap.project_id
  location                        = var.bq_location
  default_partition_expiration_ms = 31536000000
  delete_contents_on_destroy      = false
  deletion_policy                 = "PREVENT"
  labels                          = local.labels

  depends_on = [google_project_service.enabled]
}

resource "google_bigquery_table" "apply_records" {
  dataset_id          = google_bigquery_dataset.ci_records.dataset_id
  project             = google_project.bootstrap.project_id
  table_id            = "apply_records"
  deletion_protection = true

  time_partitioning {
    type          = "DAY"
    field         = "finished_at"
    expiration_ms = 31536000000
  }

  schema = jsonencode([
    { name = "apply_build_id", type = "STRING", mode = "REQUIRED" },
    { name = "plan_build_id", type = "STRING", mode = "REQUIRED" },
    { name = "layer", type = "STRING", mode = "REQUIRED" },
    { name = "state", type = "STRING", mode = "REQUIRED" },
    { name = "commit_sha", type = "STRING", mode = "REQUIRED" },
    { name = "pull_request", type = "INTEGER", mode = "NULLABLE" },
    { name = "plan_sha256", type = "STRING", mode = "REQUIRED" },
    { name = "approver", type = "STRING", mode = "NULLABLE" },
    { name = "approved_at", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "apply_identity", type = "STRING", mode = "REQUIRED" },
    { name = "started_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "finished_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "outcome", type = "STRING", mode = "REQUIRED" },
  ])
}
