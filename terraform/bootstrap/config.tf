# Non-secret inputs for CI layers, read by plan builds so real IDs stay out of the repository.

locals {
  layer_config = {
    org = {
      org_id                = var.org_id
      ai_platform_folder_id = local.ai_platform_folder_id
      platform_folder_id    = local.platform_folder_id
    }
  }
}

resource "google_storage_bucket_object" "layer_config" {
  for_each     = local.layer_config
  bucket       = google_storage_bucket.state[local.ci_layers[each.key].state_bucket].name
  name         = "config/${each.key}.auto.tfvars.json"
  content      = jsonencode(each.value)
  content_type = "application/json"
}
