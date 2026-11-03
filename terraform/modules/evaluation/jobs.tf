locals {
  run_agent = "serviceAccount:service-${var.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  harness_env = {
    PROJECT_ID          = local.sandbox
    PROJECT_NUMBER      = var.project_number
    EVAL_LOCATION       = var.region
    EVAL_DEV_BUCKET     = google_storage_bucket.dev.name
    EVAL_HELDOUT_BUCKET = google_storage_bucket.heldout.name
    EVAL_RUNS_TABLE     = "${local.sandbox}.${google_bigquery_dataset.catalog_eval.dataset_id}.${google_bigquery_table.eval_runs.table_id}"
    IMAGE_DIGEST        = split("@", var.harness_image)[1]
  }

  # Run arguments differ per evaluation, so administrators need overrides as well as run.
  eval_job_runner_permissions = [
    "run.executions.get",
    "run.executions.list",
    "run.jobs.get",
    "run.jobs.list",
    "run.jobs.run",
    "run.jobs.runWithOverrides",
    "run.operations.get",
  ]
}

# Lets sandbox Cloud Run pull the harness image from the platform repository in nonprod.
resource "google_artifact_registry_repository_iam_member" "run_agent_reader" {
  project    = local.nonprod
  location   = var.region
  repository = var.artifact_repository
  role       = "roles/artifactregistry.reader"
  member     = local.run_agent
}

# Runs one catalog evaluation per execution; the task, split, and model are passed as arguments.
resource "google_cloud_run_v2_job" "catalog_eval" {
  project             = local.sandbox
  location            = var.region
  name                = "catalog-eval"
  deletion_protection = false
  labels              = merge(local.labels, { env = "sandbox" })

  template {
    template {
      service_account = google_service_account.catalog_eval.email
      max_retries     = 0
      timeout         = "3600s"

      containers {
        image = var.harness_image

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }

        dynamic "env" {
          for_each = local.harness_env
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }

  depends_on = [google_artifact_registry_repository_iam_member.run_agent_reader]
}

# Undeploys sandbox models that have been deployed longer than the maximum age.
resource "google_cloud_run_v2_job" "endpoint_expiry" {
  project             = local.sandbox
  location            = var.region
  name                = "endpoint-expiry"
  deletion_protection = false
  labels              = merge(local.labels, { env = "sandbox" })

  template {
    template {
      service_account = google_service_account.model_deploy.email
      max_retries     = 1
      timeout         = "600s"

      containers {
        image = var.harness_image
        args  = ["expire-endpoints"]

        env {
          name  = "PROJECT_ID"
          value = local.sandbox
        }

        env {
          name  = "EVAL_LOCATION"
          value = var.region
        }

        env {
          name  = "MAX_AGE_HOURS"
          value = "4"
        }
      }
    }
  }

  depends_on = [google_artifact_registry_repository_iam_member.run_agent_reader]
}

# Starts the expiry job every hour.
resource "google_cloud_scheduler_job" "endpoint_expiry" {
  project   = local.sandbox
  region    = var.region
  name      = "endpoint-expiry"
  schedule  = "0 * * * *"
  time_zone = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/${google_cloud_run_v2_job.endpoint_expiry.id}:run"

    oauth_token {
      service_account_email = google_service_account.model_deploy.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}

# Lets the scheduler's identity start the expiry job.
resource "google_project_iam_member" "model_deploy_job_invoker" {
  project = local.sandbox
  role    = "roles/run.invoker"
  member  = google_service_account.model_deploy.member
}

# Starting jobs with per-run arguments and reading their executions.
resource "google_project_iam_custom_role" "eval_job_runner" {
  project     = local.sandbox
  role_id     = "evalJobRunner"
  title       = "Evaluation job runner"
  description = "Run sandbox jobs with argument overrides and read their executions"
  permissions = local.eval_job_runner_permissions
}

# Lets platform administrators start evaluations.
resource "google_project_iam_member" "admin_job_runner" {
  project = local.sandbox
  role    = google_project_iam_custom_role.eval_job_runner.name
  member  = "group:${var.platform_admins_group}"
}

# Lets platform administrators read job logs, including failed runs.
resource "google_project_iam_member" "admin_log_viewer" {
  project = local.sandbox
  role    = "roles/logging.viewer"
  member  = "group:${var.platform_admins_group}"
}
