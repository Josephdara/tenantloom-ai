# Existing organization access policy that will hold the prod perimeter.
resource "google_access_context_manager_access_policy" "this" {
  parent          = "organizations/${var.org_id}"
  title           = "tenantloom-ai"
  deletion_policy = "PREVENT"
}
