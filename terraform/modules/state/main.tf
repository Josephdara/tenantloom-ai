# Versioned, soft-deleted bucket for Terraform state and saved plans.
resource "google_storage_bucket" "state" {
  name                        = "${var.project_id}-tfstate"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = merge(var.labels, { env = "nonprod", purpose = "terraform-state" })

  versioning {
    enabled = true
  }

  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
      # Otherwise the provider sends age = 0, which would delete live state objects.
      send_age_if_zero = false
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = 30
      matches_prefix = ["plans/"]
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Read-only state access for pull request plans.
resource "google_storage_bucket_iam_member" "state_plan_reader" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = var.plan_reader_member
}

# CI reads these inputs at build time so real IDs stay out of the repository.
resource "google_storage_bucket_object" "ci_config" {
  bucket       = google_storage_bucket.state.name
  name         = "config/platform.auto.tfvars.json"
  content_type = "application/json"
  content      = jsonencode(var.ci_config)
}
