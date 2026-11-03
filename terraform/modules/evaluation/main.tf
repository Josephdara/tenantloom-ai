locals {
  sandbox = var.project_id
  nonprod = var.nonprod_project_id
  labels  = merge(var.labels, { purpose = "catalog-eval" })

  # Experiments records runs as metadata contexts, executions, and artifacts; nothing here deletes them.
  eval_runner_permissions = [
    "aiplatform.artifacts.create",
    "aiplatform.artifacts.get",
    "aiplatform.artifacts.list",
    "aiplatform.artifacts.update",
    "aiplatform.contexts.addContextArtifactsAndExecutions",
    "aiplatform.contexts.addContextChildren",
    "aiplatform.contexts.create",
    "aiplatform.contexts.get",
    "aiplatform.contexts.list",
    "aiplatform.contexts.update",
    "aiplatform.executions.addExecutionEvents",
    "aiplatform.executions.create",
    "aiplatform.executions.get",
    "aiplatform.executions.list",
    "aiplatform.executions.update",
    "aiplatform.locations.evaluateInstances",
    "aiplatform.locations.get",
    "aiplatform.locations.list",
    "aiplatform.metadataSchemas.create",
    "aiplatform.metadataSchemas.get",
    "aiplatform.metadataSchemas.list",
    "aiplatform.metadataStores.create",
    "aiplatform.metadataStores.get",
    "aiplatform.metadataStores.list",
  ]

  dataset_readers = {
    admins     = "group:${var.platform_admins_group}"
    governance = "group:${var.governance_group}"
  }
}

# Development split of each evaluation dataset, and reports from development runs.
resource "google_storage_bucket" "dev" {
  project                     = local.sandbox
  name                        = "${local.sandbox}-eval-dev"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = merge(local.labels, { env = "sandbox" })

  versioning {
    enabled = true
  }
}

# Held-out split and reports from held-out runs, readable only by the evaluation account. It lives in nonprod
# because the Agent Platform service agents in sandbox can read every bucket there, and sandbox identities can start
# Agent Platform workloads that run as those agents.
resource "google_storage_bucket" "heldout" {
  project                     = local.nonprod
  name                        = "${local.nonprod}-eval-heldout"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = merge(local.labels, { env = "nonprod" })

  versioning {
    enabled = true
  }
}

# Results of catalog evaluations, kept for one year.
resource "google_bigquery_dataset" "catalog_eval" {
  project                    = local.sandbox
  dataset_id                 = "catalog_eval"
  location                   = var.region
  delete_contents_on_destroy = false
  labels                     = merge(local.labels, { env = "sandbox" })
}

# One row per evaluation run, in the evaluation record schema.
resource "google_bigquery_table" "eval_runs" {
  project             = local.sandbox
  dataset_id          = google_bigquery_dataset.catalog_eval.dataset_id
  table_id            = "eval_runs"
  schema              = file("${path.module}/../../../eval/schema/eval_runs.json")
  deletion_protection = true
  labels              = merge(local.labels, { env = "sandbox" })

  time_partitioning {
    type          = "DAY"
    field         = "run_time"
    expiration_ms = 31536000000
  }
}

# Runs catalog evaluations: calls models, scores outputs, and records results.
resource "google_service_account" "catalog_eval" {
  project      = local.sandbox
  account_id   = "sa-catalog-eval"
  display_name = "Catalog evaluation"
}

# Evaluation service and Experiments access for the evaluation account.
resource "google_project_iam_custom_role" "eval_runner" {
  project     = local.sandbox
  role_id     = "evalRunner"
  title       = "Evaluation runner"
  description = "Score model outputs with the evaluation service and record runs in Experiments"
  permissions = local.eval_runner_permissions
}

# Appends rows to one table, without the delete and update permissions of BigQuery Data Editor.
resource "google_project_iam_custom_role" "eval_record_writer" {
  project     = local.sandbox
  role_id     = "evalRecordWriter"
  title       = "Evaluation record writer"
  description = "Append evaluation records to a table"
  permissions = ["bigquery.tables.get", "bigquery.tables.updateData"]
}

# Lets the evaluation account call allowlisted models and the judge model.
resource "google_project_iam_member" "catalog_eval_invoker" {
  project = local.sandbox
  role    = var.gemini_invoker_role
  member  = google_service_account.catalog_eval.member
}

# Lets the evaluation account use the evaluation service and Experiments.
resource "google_project_iam_member" "catalog_eval_runner" {
  project = local.sandbox
  role    = google_project_iam_custom_role.eval_runner.name
  member  = google_service_account.catalog_eval.member
}

# Lets the evaluation account read development data.
resource "google_storage_bucket_iam_member" "catalog_eval_dev_reader" {
  bucket = google_storage_bucket.dev.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.catalog_eval.member
}

# Lets the evaluation account write each run's report next to the split it read.
resource "google_storage_bucket_iam_member" "catalog_eval_report_writer" {
  for_each = {
    dev     = google_storage_bucket.dev.name
    heldout = google_storage_bucket.heldout.name
  }

  bucket = each.value
  role   = "roles/storage.objectCreator"
  member = google_service_account.catalog_eval.member
}

# Lets the evaluation account read held-out data; no other identity can.
resource "google_storage_bucket_iam_member" "catalog_eval_heldout_reader" {
  bucket = google_storage_bucket.heldout.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.catalog_eval.member
}

# Lets the evaluation account append run records.
resource "google_bigquery_table_iam_member" "catalog_eval_writer" {
  project    = local.sandbox
  dataset_id = google_bigquery_dataset.catalog_eval.dataset_id
  table_id   = google_bigquery_table.eval_runs.table_id
  role       = google_project_iam_custom_role.eval_record_writer.name
  member     = google_service_account.catalog_eval.member
}

# Lets platform administrators upload dataset versions, including held-out data they cannot read back.
resource "google_storage_bucket_iam_member" "admin_uploader" {
  for_each = {
    dev     = google_storage_bucket.dev.name
    heldout = google_storage_bucket.heldout.name
  }

  bucket = each.value
  role   = "roles/storage.objectCreator"
  member = "group:${var.platform_admins_group}"
}

# Lets platform administrators read development data and reports.
resource "google_storage_bucket_iam_member" "admin_dev_reader" {
  bucket = google_storage_bucket.dev.name
  role   = "roles/storage.objectViewer"
  member = "group:${var.platform_admins_group}"
}

# Lets platform administrators and governance reviewers read evaluation results.
resource "google_bigquery_dataset_iam_member" "result_reader" {
  for_each = local.dataset_readers

  project    = local.sandbox
  dataset_id = google_bigquery_dataset.catalog_eval.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}

# Lets the same readers run queries in sandbox.
resource "google_project_iam_member" "result_query" {
  for_each = local.dataset_readers

  project = local.sandbox
  role    = "roles/bigquery.jobUser"
  member  = each.value
}

# Deploys, undeploys, and expires the self-deployed candidate model in sandbox.
resource "google_service_account" "model_deploy" {
  project      = local.sandbox
  account_id   = "sa-model-deploy"
  display_name = "Sandbox model deployment"
}

# Model Garden deployment and endpoint management in sandbox only.
resource "google_project_iam_member" "model_deploy_user" {
  project = local.sandbox
  role    = "roles/aiplatform.user"
  member  = google_service_account.model_deploy.member
}

# Lets platform administrators deploy and undeploy by impersonating the deployment account.
resource "google_service_account_iam_member" "model_deploy_impersonation" {
  service_account_id = google_service_account.model_deploy.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "group:${var.platform_admins_group}"
}
