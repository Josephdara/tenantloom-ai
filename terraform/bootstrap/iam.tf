# Organization, billing account, project, bucket, and dataset grants for CI identities and groups.
# Additive bindings only; authoritative policies would drop unmanaged org bindings.

locals {
  apply = { for k, sa in google_service_account.apply : k => "serviceAccount:${sa.email}" }
  plan  = { for k, sa in google_service_account.plan : k => "serviceAccount:${sa.email}" }

  org_grants = {
    org_policy_admin   = { member = local.apply.org, role = "roles/orgpolicy.policyAdmin" }
    org_folder_admin   = { member = local.apply.org, role = "roles/resourcemanager.folderAdmin" }
    org_logging_config = { member = local.apply.org, role = "roles/logging.configWriter" }
    platform_acm_admin = { member = local.apply.platform, role = "roles/accesscontextmanager.policyAdmin" }
    plan_org_policy    = { member = local.plan.org, role = "roles/orgpolicy.policyViewer" }
    plan_org_folders   = { member = local.plan.org, role = "roles/resourcemanager.folderViewer" }
    plan_org_iam       = { member = local.plan.org, role = "roles/iam.securityReviewer" }
    plan_org_logging   = { member = local.plan.org, role = "roles/logging.viewer" }
    plan_org_viewer    = { member = local.plan.org, role = "roles/resourcemanager.organizationViewer" }
    plan_platform_acm  = { member = local.plan.platform, role = "roles/accesscontextmanager.policyReader" }
    plan_platform_fold = { member = local.plan.platform, role = "roles/resourcemanager.folderViewer" }
  }

  billing_grants = {
    org_costs     = { member = local.apply.org, role = "roles/billing.costsManager" }
    platform_user = { member = local.apply.platform, role = "roles/billing.user" }
    factory_user  = { member = local.apply.factory, role = "roles/billing.user" }
    plan_org_view = { member = local.plan.org, role = "roles/billing.viewer" }
  }

  project_grants = merge(
    { for k, m in local.apply : "logs_apply_${k}" => { member = m, role = "roles/logging.logWriter" } },
    { for k, m in local.plan : "logs_plan_${k}" => { member = m, role = "roles/logging.logWriter" } },
    { for k, m in local.apply : "builds_read_${k}" => { member = m, role = "roles/cloudbuild.builds.viewer" } },
    { for k, m in local.apply : "buckets_apply_${k}" => { member = m, role = "roles/storage.bucketViewer" } },
    { for k, m in local.plan : "buckets_plan_${k}" => { member = m, role = "roles/storage.bucketViewer" } },
    {
      gov_approve     = { member = "group:${var.governance_group}", role = "roles/cloudbuild.builds.approver" }
      gov_builds_read = { member = "group:${var.governance_group}", role = "roles/cloudbuild.builds.viewer" }
      gov_logs_read   = { member = "group:${var.governance_group}", role = "roles/logging.viewer" }
    },
  )

  bucket_grants = merge(
    {
      state_platform_org      = { bucket = local.state_buckets.platform, member = local.apply.org, role = "roles/storage.objectAdmin" }
      state_platform_platform = { bucket = local.state_buckets.platform, member = local.apply.platform, role = "roles/storage.objectAdmin" }
      state_platform_plan_org = { bucket = local.state_buckets.platform, member = local.plan.org, role = "roles/storage.objectViewer" }
      state_platform_plan_plt = { bucket = local.state_buckets.platform, member = local.plan.platform, role = "roles/storage.objectViewer" }
      state_tenant_factory    = { bucket = local.state_buckets.tenant, member = local.apply.factory, role = "roles/storage.objectAdmin" }
      state_tenant_plan       = { bucket = local.state_buckets.tenant, member = local.plan.tenant, role = "roles/storage.objectViewer" }
    },
    { for k, m in local.plan : "plans_write_${k}" => { bucket = local.plan_bucket, member = m, role = "roles/storage.objectCreator" } },
    { for k, m in local.apply : "plans_read_${k}" => { bucket = local.plan_bucket, member = m, role = "roles/storage.objectViewer" } },
    { for k, m in local.apply : "lock_${k}" => { bucket = local.lock_bucket, member = m, role = "roles/storage.objectUser" } },
  )

  dataset_grants = merge(
    { for k, m in local.apply : "write_${k}" => { member = m, role = "roles/bigquery.dataEditor" } },
    {
      read_admins     = { member = "group:${var.platform_admins_group}", role = "roles/bigquery.dataViewer" }
      read_governance = { member = "group:${var.governance_group}", role = "roles/bigquery.dataViewer" }
      read_auditors   = { member = "group:${var.auditors_group}", role = "roles/bigquery.dataViewer" }
    },
  )
}

resource "google_organization_iam_member" "grants" {
  for_each = local.org_grants
  org_id   = var.org_id
  role     = each.value.role
  member   = each.value.member
}

resource "google_billing_account_iam_member" "grants" {
  for_each           = local.billing_grants
  billing_account_id = var.billing_account
  role               = each.value.role
  member             = each.value.member
}

resource "google_project_iam_member" "grants" {
  for_each = local.project_grants
  project  = google_project.bootstrap.project_id
  role     = each.value.role
  member   = each.value.member
}

resource "google_storage_bucket_iam_member" "grants" {
  for_each = local.bucket_grants
  bucket   = each.value.bucket
  role     = each.value.role
  member   = each.value.member

  depends_on = [google_storage_bucket.state, google_storage_bucket.plans, google_storage_bucket.lock]
}

resource "google_bigquery_dataset_iam_member" "grants" {
  for_each   = local.dataset_grants
  project    = google_project.bootstrap.project_id
  dataset_id = google_bigquery_dataset.ci_records.dataset_id
  role       = each.value.role
  member     = each.value.member
}
