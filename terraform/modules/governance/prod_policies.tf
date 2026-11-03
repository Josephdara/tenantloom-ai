locals {
  prod_run_policies = {
    "run.allowedIngress"   = ["internal-and-cloud-load-balancing"]
    "run.allowedVPCEgress" = ["all-traffic"]
  }
}

# Prod Cloud Run services accept only internal and load balancer traffic and send all egress through the VPC.
resource "google_org_policy_policy" "prod_run" {
  for_each = local.prod_run_policies

  name   = "projects/${var.project_numbers["prod"]}/policies/${each.key}"
  parent = "projects/${var.project_numbers["prod"]}"

  spec {
    rules {
      values {
        allowed_values = each.value
      }
    }
  }
}
