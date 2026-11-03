# Floor settings: inspect only in sandbox, inspect and block elsewhere, wherever Agent Platform applies them.
resource "google_model_armor_floorsetting" "project" {
  for_each = var.project_ids

  parent                           = "projects/${each.value}"
  location                         = "global"
  enable_floor_setting_enforcement = true
  integrated_services              = ["AI_PLATFORM"]

  filter_config {
    pi_and_jailbreak_filter_settings {
      filter_enforcement = "ENABLED"
      confidence_level   = "MEDIUM_AND_ABOVE"
    }

    malicious_uri_filter_settings {
      filter_enforcement = "ENABLED"
    }

    sdp_settings {
      basic_config {
        filter_enforcement = "ENABLED"
      }
    }
  }

  ai_platform_floor_setting {
    inspect_only         = each.key == "sandbox" ? true : null
    inspect_and_block    = each.key == "sandbox" ? null : true
    enable_cloud_logging = true
  }
}

# Template for application-side screening through the sanitize API; floor settings were not applied to calls on the us endpoint.
resource "google_model_armor_template" "baseline" {
  for_each = local.model_test_environments

  project     = var.project_ids[each.key]
  location    = "us"
  template_id = "baseline"

  filter_config {
    pi_and_jailbreak_filter_settings {
      filter_enforcement = "ENABLED"
      confidence_level   = "MEDIUM_AND_ABOVE"
    }

    malicious_uri_filter_settings {
      filter_enforcement = "ENABLED"
    }

    sdp_settings {
      basic_config {
        filter_enforcement = "ENABLED"
      }
    }
  }

  template_metadata {
    log_sanitize_operations = true
  }
}

# Agent Platform service agent, which Google otherwise creates only on first use.
resource "google_project_service_identity" "aiplatform" {
  provider = google-beta
  for_each = var.project_ids

  project = each.value
  service = "aiplatform.googleapis.com"
}

# Lets the Agent Platform service agent call Model Armor for the floor settings.
resource "google_project_iam_member" "aiplatform_agent_model_armor" {
  for_each = var.project_ids

  project = each.value
  role    = "roles/modelarmor.user"
  member  = google_project_service_identity.aiplatform[each.key].member
}
