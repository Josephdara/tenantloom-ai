locals {
  alert_thresholds = [0.5, 0.9, 1.0]
}

# Email channel that receives platform budget alerts.
resource "google_monitoring_notification_channel" "budget_email" {
  project      = var.project_id
  display_name = "Platform budget alerts"
  type         = "email"
  user_labels  = var.labels

  labels = {
    email_address = var.alert_email
  }
}

# Monthly budget for everything under the ai-platform folder; alerts only, nothing stops spend.
resource "google_billing_budget" "platform" {
  billing_account = var.billing_account
  display_name    = "TenantLoom AI platform"

  budget_filter {
    resource_ancestors = [var.folder]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount_usd)
    }
  }

  dynamic "threshold_rules" {
    for_each = local.alert_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_email.id]
  }
}

# Destination for the Cloud Billing export used by showback.
resource "google_bigquery_dataset" "billing_export" {
  project                    = var.project_id
  dataset_id                 = "billing_export"
  location                   = var.dataset_location
  delete_contents_on_destroy = false
  labels                     = merge(var.labels, { env = "nonprod", purpose = "billing-export" })
}
