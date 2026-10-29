# PAM entitlements for temporary access to Terraform state and the apply lock.

resource "google_project_iam_member" "pam_service_agent" {
  project = google_project.bootstrap.project_id
  role    = "roles/privilegedaccessmanager.serviceAgent"
  member  = "serviceAccount:service-org-${var.org_id}@gcp-sa-pam.iam.gserviceaccount.com"

  depends_on = [google_project_service.enabled]
}

locals {
  # The bucket and its objects only, not other buckets sharing the name prefix.
  bucket_condition = { for name in concat(values(local.state_buckets), [local.lock_bucket]) :
    name => "(resource.name == \"projects/_/buckets/${name}\" || resource.name.startsWith(\"projects/_/buckets/${name}/\"))"
  }
}

resource "google_privileged_access_manager_entitlement" "state_recovery" {
  for_each = local.state_buckets

  entitlement_id       = "state-recovery-${each.key}"
  location             = "global"
  parent               = "projects/${google_project.bootstrap.project_id}"
  max_request_duration = "3600s"

  requester_justification_config {
    unstructured {}
  }

  eligible_users {
    principals = ["group:${var.platform_admins_group}"]
  }

  privileged_access {
    gcp_iam_access {
      resource      = "//cloudresourcemanager.googleapis.com/projects/${google_project.bootstrap.project_id}"
      resource_type = "cloudresourcemanager.googleapis.com/Project"

      role_bindings {
        role                 = "roles/storage.objectAdmin"
        condition_expression = "${local.bucket_condition[each.value]} || ${local.bucket_condition[local.lock_bucket]}"
      }
    }
  }

  approval_workflow {
    manual_approvals {
      require_approver_justification = true
      steps {
        approvals_needed = 1
        approvers {
          principals = ["group:${var.governance_group}"]
        }
      }
    }
  }

  depends_on = [google_project_iam_member.pam_service_agent]
}
