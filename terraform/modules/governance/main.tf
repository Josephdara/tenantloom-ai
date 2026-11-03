locals {
  data_access_services = toset([
    "aiplatform.googleapis.com",
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ])
  data_access_log_types = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]

  enforced_constraints = toset([
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "iam.disableServiceAccountKeyUpload",
    "iam.managed.disableServiceAccountKeyCreation",
    "run.managed.requireInvokerIam",
    "storage.publicAccessPrevention",
    "storage.uniformBucketLevelAccess",
  ])

  allowed_values = {
    "gcp.resourceLocations"          = ["in:us-locations"]
    "iam.allowedPolicyMemberDomains" = [data.google_organization.this.directory_customer_id]
  }

  parameterized_constraints = {
    "compute.managed.restrictProtocolForwardingCreationForTypes" = { allowedSchemes = ["INTERNAL"] }
    "essentialcontacts.managed.allowedContactDomains"            = { allowedDomains = ["@${data.google_organization.this.domain}"] }
  }

  organization_policies = merge(
    { for c in local.enforced_constraints : c => { enforce = "TRUE", deny_all = null, allowed_values = null, parameters = null } },
    { "compute.vmExternalIpAccess" = { enforce = null, deny_all = "TRUE", allowed_values = null, parameters = null } },
    { for c, v in local.allowed_values : c => { enforce = null, deny_all = null, allowed_values = v, parameters = null } },
    { for c, p in local.parameterized_constraints : c => { enforce = "TRUE", deny_all = null, allowed_values = null, parameters = jsonencode(p) } },
  )
}

data "google_organization" "this" {
  organization = "organizations/${var.org_id}"
}

# Data Access audit logs for each listed service, inherited by every project in the folder.
resource "google_folder_iam_audit_config" "data_access" {
  for_each = local.data_access_services

  folder  = var.folder
  service = each.value

  dynamic "audit_log_config" {
    for_each = local.data_access_log_types
    content {
      log_type = audit_log_config.value
    }
  }
}

# Organization policy baseline, protected from deletion through Terraform.
resource "google_org_policy_policy" "organization" {
  for_each = local.organization_policies

  name            = "organizations/${var.org_id}/policies/${each.key}"
  parent          = "organizations/${var.org_id}"
  deletion_policy = "PREVENT"

  spec {
    rules {
      enforce    = each.value.enforce
      deny_all   = each.value.deny_all
      parameters = each.value.parameters

      dynamic "values" {
        for_each = each.value.allowed_values == null ? [] : [each.value.allowed_values]
        content {
          allowed_values = values.value
        }
      }
    }
  }
}

# Denies every model in the folder until a project allowlist from the catalog overrides it.
resource "google_org_policy_policy" "folder_models" {
  name            = "${var.folder}/policies/vertexai.allowedModels"
  parent          = var.folder
  deletion_policy = "PREVENT"

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}
