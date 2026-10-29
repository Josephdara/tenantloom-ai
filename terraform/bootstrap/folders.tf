# The ai-platform and platform folders that hold the bootstrap project.

resource "google_folder" "ai_platform" {
  display_name        = "ai-platform"
  parent              = "organizations/${var.org_id}"
  deletion_protection = true
}

resource "google_folder" "platform" {
  display_name        = "platform"
  parent              = google_folder.ai_platform.name
  deletion_protection = true
}
