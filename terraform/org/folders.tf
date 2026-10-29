# The ai-platform folder and its platform, nonprod, and prod folders.

import {
  to = google_folder.ai_platform
  id = "folders/${var.ai_platform_folder_id}"
}

import {
  to = google_folder.platform
  id = "folders/${var.platform_folder_id}"
}

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

resource "google_folder" "nonprod" {
  display_name        = "nonprod"
  parent              = google_folder.ai_platform.name
  deletion_protection = true
}

resource "google_folder" "prod" {
  display_name        = "prod"
  parent              = google_folder.ai_platform.name
  deletion_protection = true
}
