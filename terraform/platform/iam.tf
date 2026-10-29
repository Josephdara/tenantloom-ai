# Read-only access for the platform plan identity on the projects this layer manages. Additive bindings only.
# Curated roles instead of Viewer, so pull request builds cannot read dataset contents or objects.

locals {
  plan_member = "serviceAccount:sa-plan-platform@${local.ci_project}.iam.gserviceaccount.com"

  plan_roles = {
    ops  = ["roles/browser", "roles/iam.securityReviewer", "roles/serviceusage.serviceUsageViewer", "roles/iam.serviceAccountViewer", "roles/bigquery.metadataViewer", "roles/artifactregistry.reader"]
    eval = ["roles/browser", "roles/iam.securityReviewer", "roles/serviceusage.serviceUsageViewer", "roles/iam.serviceAccountViewer", "roles/bigquery.metadataViewer"]
    kms  = ["roles/browser", "roles/iam.securityReviewer", "roles/serviceusage.serviceUsageViewer", "roles/cloudkms.viewer"]
  }

  plan_grants = merge([
    for p, roles in local.plan_roles : { for r in roles : "${p}/${r}" => { project = p, role = r } }
  ]...)
}

resource "google_project_iam_member" "plan" {
  for_each = local.plan_grants
  project  = google_project.shared[each.value.project].project_id
  role     = each.value.role
  member   = local.plan_member
}
