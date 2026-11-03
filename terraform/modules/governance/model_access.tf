locals {
  catalog = yamldecode(file("${path.module}/../../../catalog/catalog.yaml"))

  # Managed models are called through the API; self-deployed models are allowed only to be deployed.
  pattern_actions = {
    publisher       = "predict"
    maas            = "predict"
    "self-deployed" = "deploy"
  }

  allowed_models = {
    for env in keys(var.project_ids) : env => sort([
      for m in local.catalog.models : "publishers/${m.publisher}/models/${m.id}:${local.pattern_actions[m.deployment_pattern]}"
      if contains(m.environments, env)
    ])
  }

  model_test_environments = toset(["sandbox", "nonprod"])
}

# Per-project model allowlist generated from the catalog, replacing the folder deny-all.
resource "google_org_policy_policy" "project_models" {
  for_each = local.allowed_models

  name   = "projects/${var.project_numbers[each.key]}/policies/vertexai.allowedModels"
  parent = "projects/${var.project_numbers[each.key]}"

  spec {
    rules {
      values {
        allowed_values = each.value
      }
    }
  }
}

# Smallest permission set for calling allowlisted Gemini models.
resource "google_project_iam_custom_role" "gemini_invoker" {
  for_each = var.project_ids

  project     = each.value
  role_id     = "geminiInvoker"
  title       = "Gemini Invoker"
  description = "Call allowlisted publisher models"
  permissions = ["aiplatform.endpoints.predict"]
}

# Platform identity used to run model access tests in sandbox and nonprod.
resource "google_service_account" "model_test" {
  project      = var.project_ids["nonprod"]
  account_id   = "sa-model-test"
  display_name = "Model access test"
}

# Lets the test identity call allowlisted models in sandbox and nonprod.
resource "google_project_iam_member" "model_test_invoker" {
  for_each = local.model_test_environments

  project = var.project_ids[each.key]
  role    = google_project_iam_custom_role.gemini_invoker[each.key].name
  member  = google_service_account.model_test.member
}

# Lets the test identity screen prompts and responses with the baseline template.
resource "google_project_iam_member" "model_test_sanitizer" {
  for_each = local.model_test_environments

  project = var.project_ids[each.key]
  role    = "roles/modelarmor.user"
  member  = google_service_account.model_test.member
}

# Lets platform administrators run the tests by impersonating the test identity.
resource "google_service_account_iam_member" "model_test_impersonation" {
  service_account_id = google_service_account.model_test.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "group:${var.platform_admins_group}"
}
