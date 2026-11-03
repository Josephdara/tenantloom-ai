locals {
  github_repositories = var.github_connection_authorized ? toset(["platform"]) : toset([])
}

# Authorizing the connection stores the GitHub token through the Cloud Build service agent.
resource "google_project_iam_member" "cloudbuild_agent_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# GitHub connection, created and authorized outside Terraform, then imported.
resource "google_cloudbuildv2_connection" "github" {
  for_each = local.github_repositories

  project  = var.project_id
  location = var.region
  name     = var.github_connection_name

  github_config {
    app_installation_id = var.github_app_installation_id

    authorizer_credential {
      oauth_token_secret_version = var.github_oauth_token_secret_version
    }
  }

  depends_on = [google_project_iam_member.cloudbuild_agent_secrets]
}

# Link to this repository, created once the connection is authorized.
resource "google_cloudbuildv2_repository" "platform" {
  for_each = local.github_repositories

  project           = var.project_id
  location          = var.region
  name              = "tenantloom-ai"
  parent_connection = google_cloudbuildv2_connection.github[each.key].name
  remote_uri        = var.platform_repo_uri
}

# Read-only plan for each pull request to main.
resource "google_cloudbuild_trigger" "pr_plan" {
  for_each = local.github_repositories

  project         = var.project_id
  location        = var.region
  name            = "platform-pr-plan"
  service_account = var.terraform_plan_service_account
  filename        = "cloudbuild/pr-plan.yaml"
  substitutions   = { _STATE_BUCKET = var.state_bucket }

  repository_event_config {
    repository = google_cloudbuildv2_repository.platform[each.key].id

    pull_request {
      branch          = "^main$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }
}

# Plan saved for each merge to main, run only after approval.
resource "google_cloudbuild_trigger" "merge_plan" {
  for_each = local.github_repositories

  project         = var.project_id
  location        = var.region
  name            = "platform-merge-plan"
  service_account = var.terraform_service_account
  filename        = "cloudbuild/plan.yaml"
  substitutions = {
    _STATE_BUCKET  = var.state_bucket
    _APPLY_TRIGGER = google_cloudbuild_trigger.apply[each.key].trigger_id
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.platform[each.key].id

    push {
      branch = "^main$"
    }
  }

  approval_config {
    approval_required = true
  }
}

# Started only by the merge plan build, so an apply always has a saved plan for its commit.
resource "google_cloudbuild_trigger" "apply" {
  for_each = local.github_repositories

  project         = var.project_id
  location        = var.region
  name            = "platform-apply"
  service_account = var.terraform_service_account
  substitutions   = { _STATE_BUCKET = var.state_bucket }

  source_to_build {
    repository = google_cloudbuildv2_repository.platform[each.key].id
    ref        = "refs/heads/main"
    repo_type  = "GITHUB"
  }

  git_file_source {
    path       = "cloudbuild/apply.yaml"
    repository = google_cloudbuildv2_repository.platform[each.key].id
    revision   = "refs/heads/main"
    repo_type  = "GITHUB"
  }

  approval_config {
    approval_required = true
  }
}

# Platform container images, such as the evaluation harness.
resource "google_artifact_registry_repository" "platform" {
  project       = var.project_id
  location      = var.region
  repository_id = "platform"
  format        = "DOCKER"
  description   = "Platform-owned container images"

  docker_config {
    immutable_tags = true
  }
}

# Builds platform images; holds no project-level storage or build roles.
resource "google_service_account" "eval_build" {
  project      = var.project_id
  account_id   = "sa-eval-build"
  display_name = "Platform image build"
}

# Lets image builds write their own logs.
resource "google_project_iam_member" "eval_build_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.eval_build.member
}

# Lets image builds push to the platform repository only.
resource "google_artifact_registry_repository_iam_member" "eval_build_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.platform.repository_id
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.eval_build.member
}

# Builds the evaluation harness image for each merge that changes eval/.
resource "google_cloudbuild_trigger" "eval_image" {
  for_each = local.github_repositories

  project         = var.project_id
  location        = var.region
  name            = "platform-eval-image"
  service_account = google_service_account.eval_build.id
  filename        = "cloudbuild/eval-image.yaml"
  included_files  = ["eval/**", "cloudbuild/eval-image.yaml"]
  substitutions = {
    _IMAGE = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.platform.repository_id}/eval-harness"
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.platform[each.key].id

    push {
      branch = "^main$"
    }
  }
}
