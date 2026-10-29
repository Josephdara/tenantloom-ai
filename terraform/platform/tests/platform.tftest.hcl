# Offline checks of the platform layer's boundaries, using a mocked Google provider.

mock_provider "google" {
  mock_resource "google_access_context_manager_access_policy" {
    defaults = {
      name = "123456789"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      member = "serviceAccount:sa-harness-build@jd-aip-ops.iam.gserviceaccount.com"
    }
  }
}

variables {
  org_id             = "100000000000"
  billing_account    = "000000-000000-000000"
  platform_folder_id = "200000000000"
}

run "shared_projects_are_protected_and_in_the_platform_folder" {
  command = apply

  assert {
    condition     = toset(keys(google_project.shared)) == toset(["ops", "eval", "kms"])
    error_message = "Expected exactly the ops, eval, and kms projects."
  }

  assert {
    condition     = alltrue([for p in google_project.shared : p.deletion_policy == "PREVENT" && p.folder_id == var.platform_folder_id && !p.auto_create_network])
    error_message = "Shared projects must be deletion-protected, in the platform folder, and without a default network."
  }

  assert {
    condition     = alltrue([for d in google_bigquery_dataset.shared : d.deletion_policy == "PREVENT" && !d.delete_contents_on_destroy])
    error_message = "Shared datasets must be deletion-protected."
  }
}

run "test_perimeter_is_dry_run_only" {
  command = apply

  assert {
    condition     = google_access_context_manager_service_perimeter.test.use_explicit_dry_run_spec && length(google_access_context_manager_service_perimeter.test.status) == 0
    error_message = "The test perimeter must have no enforced configuration."
  }

  assert {
    condition     = length(google_access_context_manager_service_perimeter.test.spec[0].resources) == 0
    error_message = "The test perimeter must start with no member projects."
  }

  assert {
    condition     = contains(google_access_context_manager_service_perimeter.test.spec[0].restricted_services, "aiplatform.googleapis.com")
    error_message = "Agent Platform must be a restricted service."
  }
}

run "plan_identity_cannot_read_data" {
  command = apply

  assert {
    condition = alltrue([
      for g in google_project_iam_member.plan :
      !contains(["roles/viewer", "roles/editor", "roles/owner", "roles/bigquery.dataViewer", "roles/storage.objectViewer"], g.role)
    ])
    error_message = "The plan identity must not hold roles that read dataset contents or objects."
  }

  assert {
    condition     = alltrue([for g in google_project_iam_member.plan : g.member == "serviceAccount:sa-plan-platform@jd-aip-bootstrap.iam.gserviceaccount.com"])
    error_message = "Plan grants must go only to the platform plan identity."
  }
}

run "harness_tags_are_immutable" {
  command = apply

  assert {
    condition     = google_artifact_registry_repository.harness.docker_config[0].immutable_tags
    error_message = "Harness tags must be immutable."
  }
}
