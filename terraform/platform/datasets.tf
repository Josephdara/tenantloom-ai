# Evaluation results, access review, and showback datasets. Tables are added per tenant and per report.

locals {
  datasets = {
    eval_runs      = local.host["eval"]
    access_reviews = "ops"
    showback       = "ops"
  }
}

resource "google_bigquery_dataset" "shared" {
  for_each                   = local.datasets
  project                    = google_project.shared[each.value].project_id
  dataset_id                 = each.key
  location                   = var.bq_location
  delete_contents_on_destroy = false
  deletion_policy            = "PREVENT"
  labels                     = { component = each.value, managed-by = "terraform" }

  depends_on = [google_project_service.shared]
}
