# Buckets for Terraform state, saved plans, and the CI apply lock.

resource "google_storage_bucket" "state" {
  for_each = local.state_buckets

  name                        = each.value
  project                     = google_project.bootstrap.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  deletion_policy             = "PREVENT"
  labels                      = merge(local.labels, { purpose = "${each.key}-state" })

  versioning {
    enabled = true
  }

  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 90
      # Otherwise the provider sends age = 0, which would delete live state objects.
      send_age_if_zero = false
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.enabled]
}

resource "google_storage_bucket" "plans" {
  name                        = local.plan_bucket
  project                     = google_project.bootstrap.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = merge(local.labels, { purpose = "saved-plans" })

  versioning {
    enabled = false
  }

  soft_delete_policy {
    retention_duration_seconds = 0
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.enabled]
}

resource "google_storage_bucket" "lock" {
  name                        = local.lock_bucket
  project                     = google_project.bootstrap.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = merge(local.labels, { purpose = "apply-lock" })

  versioning {
    enabled = false
  }

  soft_delete_policy {
    retention_duration_seconds = 0
  }

  depends_on = [google_project_service.enabled]
}
