locals {
  environments    = toset(keys(var.project_ids))
  nonprod_project = var.project_ids["nonprod"]

  terraform_org_roles = toset([
    "roles/accesscontextmanager.policyAdmin",
    "roles/iam.organizationRoleViewer",
    "roles/orgpolicy.policyAdmin",
  ])

  terraform_billing_roles = toset([
    "roles/billing.costsManager",
    "roles/billing.user",
  ])

  terraform_folder_roles = toset([
    "roles/artifactregistry.admin",
    "roles/bigquery.dataOwner",
    "roles/billing.projectManager",
    "roles/binaryauthorization.attestorsAdmin",
    "roles/binaryauthorization.policyEditor",
    "roles/cloudbuild.builds.editor",
    "roles/cloudbuild.connectionAdmin",
    "roles/clouddeploy.admin",
    "roles/cloudkms.admin",
    "roles/cloudquotas.admin",
    "roles/cloudscheduler.admin",
    "roles/compute.loadBalancerAdmin",
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/containeranalysis.admin",
    "roles/dns.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/logging.admin",
    "roles/modelarmor.admin",
    "roles/modelarmor.floorSettingsAdmin",
    "roles/monitoring.editor",
    "roles/privilegedaccessmanager.admin",
    "roles/resourcemanager.folderIamAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/run.developer",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/storage.admin",
  ])

  plan_org_roles = toset([
    "roles/accesscontextmanager.policyReader",
    "roles/iam.organizationRoleViewer",
    "roles/orgpolicy.policyViewer",
  ])

  plan_folder_roles = toset([
    "roles/cloudbuild.connectionViewer",
    "roles/cloudkms.viewer",
    "roles/cloudquotas.viewer",
    "roles/compute.networkViewer",
    "roles/dns.reader",
    "roles/iam.securityReviewer",
    "roles/modelarmor.floorSettingsViewer",
    "roles/modelarmor.viewer",
    "roles/privilegedaccessmanager.viewer",
    "roles/resourcemanager.folderViewer",
    "roles/run.viewer",
  ])

  # Read access for planning, without job creation, log-entry reads, or secret access.
  plan_reader_permissions = [
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.getIamPolicy",
    "bigquery.datasets.get",
    "bigquery.datasets.getIamPolicy",
    "bigquery.tables.get",
    "bigquery.tables.getIamPolicy",
    "cloudbuild.builds.get",
    "cloudbuild.builds.list",
    "clouddeploy.automations.get",
    "clouddeploy.deliveryPipelines.get",
    "clouddeploy.deliveryPipelines.getIamPolicy",
    "clouddeploy.targets.get",
    "clouddeploy.targets.getIamPolicy",
    "cloudscheduler.jobs.get",
    "compute.regionNetworkEndpointGroups.get",
    "iam.roles.get",
    "iam.roles.list",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.list",
    "logging.buckets.get",
    "logging.exclusions.get",
    "logging.logMetrics.get",
    "logging.settings.get",
    "logging.sinks.get",
    "logging.views.get",
    "logging.views.getIamPolicy",
    "monitoring.alertPolicies.get",
    "monitoring.dashboards.get",
    "monitoring.notificationChannels.get",
    "monitoring.notificationChannels.list",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "serviceusage.services.get",
    "serviceusage.services.list",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.list",
  ]
}

# Applies platform and tenant changes from approved merge builds.
resource "google_service_account" "terraform" {
  project      = local.nonprod_project
  account_id   = "sa-terraform"
  display_name = "Platform Terraform apply"
}

# Plans pull requests with read-only access.
resource "google_service_account" "terraform_plan" {
  project      = local.nonprod_project
  account_id   = "sa-terraform-plan"
  display_name = "Platform Terraform read-only plan"
}

# Organization policy and access policy administration, plus org IAM read.
resource "google_organization_iam_member" "terraform" {
  for_each = local.terraform_org_roles

  org_id = var.org_id
  role   = each.value
  member = google_service_account.terraform.member
}

# Budgets and project billing links.
resource "google_billing_account_iam_member" "terraform" {
  for_each = local.terraform_billing_roles

  billing_account_id = var.billing_account
  role               = each.value
  member             = google_service_account.terraform.member
}

# Admin roles for each service the platform manages in the three projects.
resource "google_folder_iam_member" "terraform" {
  for_each = local.terraform_folder_roles

  folder = var.folder
  role   = each.value
  member = google_service_account.terraform.member
}

# Custom role management in each project.
resource "google_project_iam_member" "terraform_role_admin" {
  for_each = local.environments

  project = var.project_ids[each.key]
  role    = "roles/iam.roleAdmin"
  member  = google_service_account.terraform.member
}

# Read access to organization policies, the access policy, and org IAM.
resource "google_organization_iam_member" "terraform_plan" {
  for_each = local.plan_org_roles

  org_id = var.org_id
  role   = each.value
  member = google_service_account.terraform_plan.member
}

# Read access to the billing account and its budgets.
resource "google_billing_account_iam_member" "terraform_plan" {
  billing_account_id = var.billing_account
  role               = "roles/billing.viewer"
  member             = google_service_account.terraform_plan.member
}

# Read access to the folder and the services the platform manages.
resource "google_folder_iam_member" "terraform_plan" {
  for_each = local.plan_folder_roles

  folder = var.folder
  role   = each.value
  member = google_service_account.terraform_plan.member
}

# Reads the folder audit sink; the organization role is created outside Terraform because no predefined role reads sinks without log entries.
resource "google_folder_iam_member" "terraform_plan_log_config_reader" {
  folder = var.folder
  role   = "organizations/${var.org_id}/roles/terraformLogConfigReader"
  member = google_service_account.terraform_plan.member
}

# Get and list permissions Terraform needs to plan in each project.
resource "google_project_iam_custom_role" "plan_reader" {
  for_each = local.environments

  project     = var.project_ids[each.key]
  role_id     = "terraformPlanReader"
  title       = "Terraform plan reader"
  permissions = local.plan_reader_permissions
}

# Grants the plan reader role in each project.
resource "google_project_iam_member" "terraform_plan_reader" {
  for_each = local.environments

  project = var.project_ids[each.key]
  role    = google_project_iam_custom_role.plan_reader[each.key].name
  member  = google_service_account.terraform_plan.member
}

# Lets pull request builds write their logs.
resource "google_project_iam_member" "terraform_plan_log_writer" {
  project = local.nonprod_project
  role    = "roles/logging.logWriter"
  member  = google_service_account.terraform_plan.member
}

# Lets ai-governance approve merge plan and apply builds.
resource "google_project_iam_member" "governance_build_approver" {
  project = local.nonprod_project
  role    = "roles/cloudbuild.builds.approver"
  member  = "group:${var.governance_group}"
}

# Log view limited to Cloud Build logs, so approvers can read the plans they approve.
resource "google_logging_log_view" "cloudbuild" {
  name        = "cloudbuild"
  bucket      = "projects/${local.nonprod_project}/locations/global/buckets/_Default"
  description = "Cloud Build logs for platform plan and apply builds"
  filter      = "LOG_ID(\"cloudbuild\")"
}

# Lets ai-governance read build logs through the Cloud Build view only.
resource "google_logging_log_view_iam_member" "governance_build_log_reader" {
  parent   = "projects/${local.nonprod_project}"
  location = "global"
  bucket   = "_Default"
  name     = google_logging_log_view.cloudbuild.name
  role     = "roles/logging.viewAccessor"
  member   = "group:${var.governance_group}"
}
