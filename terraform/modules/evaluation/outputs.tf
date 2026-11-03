output "catalog_eval_service_account" {
  value = google_service_account.catalog_eval.email
}

output "model_deploy_service_account" {
  value = google_service_account.model_deploy.email
}

output "buckets" {
  value = {
    dev     = google_storage_bucket.dev.name
    heldout = google_storage_bucket.heldout.name
  }
}

output "eval_runs_table" {
  value = "${google_bigquery_table.eval_runs.project}.${google_bigquery_dataset.catalog_eval.dataset_id}.${google_bigquery_table.eval_runs.table_id}"
}
