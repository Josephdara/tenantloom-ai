locals {
  restricted_range = "199.36.153.4/30"
  restricted_ips   = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
  restricted_names = {
    googleapis = "*.googleapis.com."
    run-app    = "*.run.app."
  }
}

# Prod VPC that carries all Cloud Run egress.
resource "google_compute_network" "prod" {
  project                 = var.project_id
  name                    = "prod"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Subnet for Direct VPC egress, with Private Google Access to reach Google APIs without public IPs.
resource "google_compute_subnetwork" "prod" {
  project                  = var.project_id
  name                     = "prod-${var.region}"
  region                   = var.region
  network                  = google_compute_network.prod.id
  ip_cidr_range            = "10.10.0.0/24"
  private_ip_google_access = true
}

# Blocks all egress that a higher-priority rule does not allow.
resource "google_compute_firewall" "deny_all_egress" {
  project            = var.project_id
  name               = "deny-all-egress"
  network            = google_compute_network.prod.id
  direction          = "EGRESS"
  priority           = 65534
  destination_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

# Allows HTTPS to the restricted Google API range only.
resource "google_compute_firewall" "allow_restricted_apis" {
  project            = var.project_id
  name               = "allow-restricted-google-apis"
  network            = google_compute_network.prod.id
  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = [local.restricted_range]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

# Resolves Google API and Cloud Run names inside the VPC to the restricted range.
resource "google_dns_response_policy" "restricted_apis" {
  project              = var.project_id
  response_policy_name = "restricted-google-apis"
  description          = "Send Google API traffic to restricted.googleapis.com"

  networks {
    network_url = google_compute_network.prod.id
  }
}

# Resolves every Google API and run.app name to the restricted range.
resource "google_dns_response_policy_rule" "restricted" {
  for_each = local.restricted_names

  project         = var.project_id
  response_policy = google_dns_response_policy.restricted_apis.response_policy_name
  rule_name       = each.key
  dns_name        = each.value

  local_data {
    local_datas {
      name    = each.value
      type    = "A"
      ttl     = 300
      rrdatas = local.restricted_ips
    }
  }
}

# Public zone for the prod hostname, delegated from the parent domain at its registrar.
resource "google_dns_managed_zone" "prod" {
  project     = var.project_id
  name        = "prod-hostname"
  dns_name    = "${var.hostname}."
  description = "Prod load balancer hostname"
  visibility  = "public"
  labels      = var.labels
}

# Static address for the prod load balancer.
resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "prod-lb"
}

# Points the prod hostname at the load balancer.
resource "google_dns_record_set" "lb" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.prod.name
  name         = "${var.hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb.address]
}

# Google-managed certificate, issued once the hostname resolves to the load balancer.
resource "google_compute_managed_ssl_certificate" "prod" {
  project = var.project_id
  name    = "prod-hostname"

  managed {
    domains = [var.hostname]
  }
}
