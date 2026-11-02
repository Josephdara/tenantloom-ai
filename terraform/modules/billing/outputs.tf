output "budget" {
  value = google_billing_budget.platform.name
}

output "billing_export_dataset" {
  value = google_bigquery_dataset.billing_export.id
}
