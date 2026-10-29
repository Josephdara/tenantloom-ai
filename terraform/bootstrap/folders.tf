# Lookups for the ai-platform and platform folders, which the org layer now manages.

removed {
  from = google_folder.ai_platform

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_folder.platform

  lifecycle {
    destroy = false
  }
}

data "google_active_folder" "ai_platform" {
  display_name = "ai-platform"
  parent       = "organizations/${var.org_id}"
}

data "google_active_folder" "platform" {
  display_name = "platform"
  parent       = data.google_active_folder.ai_platform.name
}
