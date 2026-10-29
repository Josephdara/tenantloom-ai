# Folder grants for project creation by the platform and tenant layers. Additive bindings only.

locals {
  folder_grants = {
    factory_create_nonprod   = { folder = google_folder.nonprod.name, member = local.sa["sa-factory"], role = "roles/resourcemanager.projectCreator" }
    factory_create_prod      = { folder = google_folder.prod.name, member = local.sa["sa-factory"], role = "roles/resourcemanager.projectCreator" }
    platform_create          = { folder = google_folder.platform.name, member = local.sa["sa-platform"], role = "roles/resourcemanager.projectCreator" }
    platform_view_nonprod    = { folder = google_folder.nonprod.name, member = local.sa["sa-platform"], role = "roles/resourcemanager.folderViewer" }
    platform_view_prod       = { folder = google_folder.prod.name, member = local.sa["sa-platform"], role = "roles/resourcemanager.folderViewer" }
    plan_tenant_view_nonprod = { folder = google_folder.nonprod.name, member = local.sa["sa-plan-tenant"], role = "roles/resourcemanager.folderViewer" }
    plan_tenant_view_prod    = { folder = google_folder.prod.name, member = local.sa["sa-plan-tenant"], role = "roles/resourcemanager.folderViewer" }
  }
}

resource "google_folder_iam_member" "grants" {
  for_each = local.folder_grants
  folder   = each.value.folder
  role     = each.value.role
  member   = each.value.member
}
