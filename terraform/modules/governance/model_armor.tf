# Model Armor screens every Agent Platform request: inspect only in sandbox, inspect and block elsewhere.
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

# Lets the Agent Platform service agent call Model Armor for the floor settings.
resource "google_project_iam_member" "aiplatform_agent_model_armor" {
  for_each = var.project_numbers

  project = var.project_ids[each.key]
  role    = "roles/modelarmor.user"
  member  = "serviceAccount:service-${each.value}@gcp-sa-aiplatform.iam.gserviceaccount.com"
}
