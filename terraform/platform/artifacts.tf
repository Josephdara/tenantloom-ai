# Evaluation harness image repository, gate bundle repository, and the identity that publishes the harness.

resource "google_artifact_registry_repository" "harness" {
  project       = google_project.shared["ops"].project_id
  location      = var.region
  repository_id = "harness"
  format        = "DOCKER"
  description   = "Evaluation harness images, referenced by digest."

  # Jobs pin the harness by digest, so a tag must never move to a different image.
  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.shared]
}

resource "google_artifact_registry_repository" "gates" {
  project       = google_project.shared["ops"].project_id
  location      = var.region
  repository_id = "gates"
  format        = "GENERIC"
  description   = "Versioned gate bundles: mandatory checks, thresholds, and the gate runner."

  depends_on = [google_project_service.shared]
}

resource "google_service_account" "harness_build" {
  project      = google_project.shared["ops"].project_id
  account_id   = "sa-harness-build"
  display_name = "Evaluation harness build and publication"

  depends_on = [google_project_service.shared]
}

resource "google_artifact_registry_repository_iam_member" "harness_writer" {
  project    = google_artifact_registry_repository.harness.project
  location   = google_artifact_registry_repository.harness.location
  repository = google_artifact_registry_repository.harness.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.harness_build.member
}
