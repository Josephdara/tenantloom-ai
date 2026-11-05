output "dataset" {
  value = google_bigquery_dataset.tenant_eval.dataset_id
}

output "eval_runner_role" {
  value = google_project_iam_custom_role.eval_runner.name
}

output "eval_record_writer_role" {
  value = google_project_iam_custom_role.eval_record_writer.name
}
