# GitHub connection for infrastructure CI and the link to the platform repository.

# The connection is created in the console, where the GitHub App is authorized.
import {
  to = google_cloudbuildv2_connection.github
  id = "projects/${local.project_id}/locations/${var.region}/connections/${var.github_connection_name}"
}

resource "google_cloudbuildv2_connection" "github" {
  project  = google_project.bootstrap.project_id
  location = var.region
  name     = var.github_connection_name

  github_config {
    app_installation_id = var.github_app_installation_id

    authorizer_credential {
      oauth_token_secret_version = var.github_oauth_token_secret_version
    }
  }
}

resource "google_cloudbuildv2_repository" "platform" {
  project           = google_project.bootstrap.project_id
  location          = var.region
  name              = "tenantloom-ai"
  parent_connection = google_cloudbuildv2_connection.github.name
  remote_uri        = var.platform_repo_uri
}
