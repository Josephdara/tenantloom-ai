# The ai-platform folder and its platform folder, created by bootstrap and owned by this layer.

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
