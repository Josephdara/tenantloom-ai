locals {
  prod_resource = "//cloudresourcemanager.googleapis.com/projects/${var.project_ids["prod"]}"
}

# Privileged Access Manager acts through the organization-level service agent, created outside Terraform.
resource "google_project_iam_member" "pam_agent" {
  project = var.project_ids["prod"]
  role    = "roles/privilegedaccessmanager.serviceAgent"
  member  = "serviceAccount:service-org-${var.org_id}@gcp-sa-pam.iam.gserviceaccount.com"
}

# Time-bound prod administration for platform admins, approved by ai-governance; no role in it can change IAM.
resource "google_privileged_access_manager_entitlement" "platform_prod_admin" {
  parent               = "projects/${var.project_ids["prod"]}"
  location             = "global"
  entitlement_id       = "platform-prod-admin"
  max_request_duration = "3600s"

  eligible_users {
    principals = ["group:${var.platform_admins_group}"]
  }

  privileged_access {
    gcp_iam_access {
      resource      = local.prod_resource
      resource_type = "cloudresourcemanager.googleapis.com/Project"

      role_bindings {
        role = "roles/run.developer"
      }

      role_bindings {
        role = "roles/run.invoker"
      }

      role_bindings {
        role = "roles/aiplatform.user"
      }

      role_bindings {
        role = "roles/logging.viewAccessor"
      }
    }
  }

  requester_justification_config {
    unstructured {}
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

  depends_on = [google_project_iam_member.pam_agent]
}
