# Organization and folder policy baseline.

locals {
  org_parent = "organizations/${var.org_id}"

  # Set by the organization's secure-by-default setup before Terraform managed it.
  imported_org_policies = [
    "storage.uniformBucketLevelAccess",
    "iam.managed.disableServiceAccountKeyCreation",
    "iam.disableServiceAccountKeyUpload",
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "essentialcontacts.managed.allowedContactDomains",
    "compute.managed.restrictProtocolForwardingCreationForTypes",
  ]

  enforced_org_policies = {
    "storage.uniformBucketLevelAccess"                           = null
    "iam.managed.disableServiceAccountKeyCreation"               = null
    "iam.disableServiceAccountKeyUpload"                         = null
    "iam.automaticIamGrantsForDefaultServiceAccounts"            = null
    "essentialcontacts.managed.allowedContactDomains"            = jsonencode({ allowedDomains = ["@${local.domain}"] })
    "compute.managed.restrictProtocolForwardingCreationForTypes" = jsonencode({ allowedSchemes = ["INTERNAL"] })
    "storage.publicAccessPrevention"                             = null
    "run.managed.requireInvokerIam"                              = null
  }
}

import {
  for_each = toset(local.imported_org_policies)
  to       = google_org_policy_policy.org_enforced[each.key]
  id       = "${local.org_parent}/policies/${each.key}"
}

resource "google_org_policy_policy" "org_enforced" {
  for_each = local.enforced_org_policies
  name     = "${local.org_parent}/policies/${each.key}"
  parent   = local.org_parent

  spec {
    rules {
      enforce    = "TRUE"
      parameters = each.value
    }
  }
}

resource "google_org_policy_policy" "vm_external_ip" {
  name   = "${local.org_parent}/policies/compute.vmExternalIpAccess"
  parent = local.org_parent

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

import {
  to = google_org_policy_policy.allowed_member_domains
  id = "${local.org_parent}/policies/iam.allowedPolicyMemberDomains"
}

resource "google_org_policy_policy" "allowed_member_domains" {
  name   = "${local.org_parent}/policies/iam.allowedPolicyMemberDomains"
  parent = local.org_parent

  spec {
    rules {
      values {
        allowed_values = [data.google_organization.this.directory_customer_id]
      }
    }
  }
}

resource "google_org_policy_policy" "resource_locations" {
  name   = "${local.org_parent}/policies/gcp.resourceLocations"
  parent = local.org_parent

  spec {
    rules {
      values {
        allowed_values = ["in:us-locations"]
      }
    }
  }
}

resource "google_org_policy_policy" "allowed_models_default" {
  name   = "${google_folder.ai_platform.name}/policies/vertexai.allowedModels"
  parent = google_folder.ai_platform.name

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "prod_binauthz" {
  name   = "${google_folder.prod.name}/policies/run.allowedBinaryAuthorizationPolicies"
  parent = google_folder.prod.name

  spec {
    rules {
      values {
        allowed_values = ["default"]
      }
    }
  }
}
