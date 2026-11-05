locals {
  labels = merge(var.labels, { env = "nonprod", purpose = "tenant-eval" })
}

# Shared dataset for per-team evaluation tables; each tenant state owns its own table and grants.
resource "google_bigquery_dataset" "tenant_eval" {
  project                    = var.project_id
  dataset_id                 = "tenant_eval"
  location                   = var.region
  delete_contents_on_destroy = false
  labels                     = local.labels
}

# Evaluation service and Experiments access for team evaluation accounts, matching the catalog evaluation role.
resource "google_project_iam_custom_role" "eval_runner" {
  project     = var.project_id
  role_id     = "evalRunner"
  title       = "Evaluation runner"
  description = "Score service outputs with the evaluation service and record runs in Experiments"
  permissions = var.eval_runner_permissions
}

# Appends rows to one table, without the delete and update permissions of BigQuery Data Editor.
resource "google_project_iam_custom_role" "eval_record_writer" {
  project     = var.project_id
  role_id     = "evalRecordWriter"
  title       = "Evaluation record writer"
  description = "Append evaluation records to a table"
  permissions = ["bigquery.tables.get", "bigquery.tables.updateData"]
}
