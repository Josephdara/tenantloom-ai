# Organization lookup for the domain and customer ID, and the CI identities this layer grants roles to.

data "google_organization" "this" {
  organization = "organizations/${var.org_id}"
}

locals {
  domain     = data.google_organization.this.domain
  ci_project = "${var.project_prefix}bootstrap"

  sa = {
    for name in ["sa-factory", "sa-platform", "sa-plan-tenant"] :
    name => "serviceAccount:${name}@${local.ci_project}.iam.gserviceaccount.com"
  }
}
