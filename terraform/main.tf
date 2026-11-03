locals {
  labels = {
    component  = "platform"
    managed-by = "terraform"
  }
}

import {
  to = google_folder.ai_platform
  id = "folders/${var.folder_id}"
}

import {
  for_each = var.github_connection_authorized ? toset(["platform"]) : toset([])
  to       = module.cloudbuild.google_cloudbuildv2_connection.github[each.key]
  id       = "projects/${var.project_prefix}nonprod/locations/${var.region}/connections/${var.github_connection_name}"
}

import {
  for_each = toset(["aiplatform.googleapis.com", "iam.googleapis.com"])
  to       = module.governance.google_folder_iam_audit_config.data_access[each.key]
  id       = "folders/${var.folder_id} ${each.key}"
}

import {
  for_each = toset([
    "compute.managed.restrictProtocolForwardingCreationForTypes",
    "compute.vmExternalIpAccess",
    "essentialcontacts.managed.allowedContactDomains",
    "gcp.resourceLocations",
    "iam.allowedPolicyMemberDomains",
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "iam.disableServiceAccountKeyUpload",
    "iam.managed.disableServiceAccountKeyCreation",
    "run.managed.requireInvokerIam",
    "storage.publicAccessPrevention",
    "storage.uniformBucketLevelAccess",
  ])
  to = module.governance.google_org_policy_policy.organization[each.key]
  id = "organizations/${var.org_id}/policies/${each.key}"
}

import {
  to = module.governance.google_org_policy_policy.folder_models
  id = "folders/${var.folder_id}/policies/vertexai.allowedModels"
}

import {
  to = module.perimeter.google_access_context_manager_access_policy.this
  id = var.access_policy_id
}

# Existing ai-platform folder, imported so platform state owns it.
resource "google_folder" "ai_platform" {
  display_name        = "ai-platform"
  parent              = "organizations/${var.org_id}"
  deletion_protection = true
}

module "projects" {
  source = "./modules/projects"

  folder_id       = google_folder.ai_platform.folder_id
  billing_account = var.billing_account
  project_prefix  = var.project_prefix
  labels          = local.labels
}

module "governance" {
  source = "./modules/governance"

  org_id = var.org_id
  folder = google_folder.ai_platform.name
}

module "perimeter" {
  source = "./modules/perimeter"

  org_id = var.org_id
}

module "ci_identities" {
  source = "./modules/ci-identities"

  org_id           = var.org_id
  billing_account  = var.billing_account
  folder           = google_folder.ai_platform.name
  project_ids      = module.projects.project_ids
  governance_group = var.governance_group
}

module "state" {
  source = "./modules/state"

  project_id         = module.projects.project_ids["nonprod"]
  region             = var.region
  labels             = local.labels
  plan_reader_member = module.ci_identities.terraform_plan.member

  ci_config = {
    org_id                            = var.org_id
    billing_account                   = var.billing_account
    folder_id                         = var.folder_id
    region                            = var.region
    project_prefix                    = var.project_prefix
    governance_group                  = var.governance_group
    platform_repo_uri                 = var.platform_repo_uri
    github_connection_name            = var.github_connection_name
    github_connection_authorized      = var.github_connection_authorized
    github_app_installation_id        = var.github_app_installation_id
    github_oauth_token_secret_version = var.github_oauth_token_secret_version
    budget_alert_email                = var.budget_alert_email
    access_policy_id                  = var.access_policy_id
    prod_hostname                     = var.prod_hostname
    platform_admins_group             = var.platform_admins_group
    auditors_group                    = var.auditors_group
  }
}

module "billing" {
  source = "./modules/billing"

  project_id      = module.projects.project_ids["nonprod"]
  folder          = google_folder.ai_platform.name
  billing_account = var.billing_account
  budget_amount   = var.budget_amount
  alert_email     = var.budget_alert_email
  labels          = local.labels
}

module "cloudbuild" {
  source = "./modules/cloudbuild"

  project_id                        = module.projects.project_ids["nonprod"]
  project_number                    = module.projects.project_numbers["nonprod"]
  region                            = var.region
  state_bucket                      = module.state.bucket
  terraform_service_account         = module.ci_identities.terraform.id
  terraform_plan_service_account    = module.ci_identities.terraform_plan.id
  platform_repo_uri                 = var.platform_repo_uri
  github_connection_name            = var.github_connection_name
  github_connection_authorized      = var.github_connection_authorized
  github_app_installation_id        = var.github_app_installation_id
  github_oauth_token_secret_version = var.github_oauth_token_secret_version
}
