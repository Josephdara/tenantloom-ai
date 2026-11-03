locals {
  prod            = var.project_ids["prod"]
  egress_test_url = "https://${var.region}-aiplatform.googleapis.com/v1/projects/${local.prod}/locations/${var.region}/publishers/google/models/${var.model}:generateContent"
}

# Cloud Run service agent in prod, which Google otherwise creates only on first use.
resource "google_project_service_identity" "run" {
  provider = google-beta

  project = local.prod
  service = "run.googleapis.com"
}

# Runtime identity for the temporary prod probe service and egress test job.
resource "google_service_account" "probe" {
  project      = local.prod
  account_id   = "sa-platform-probe"
  display_name = "Prod network probe"
}

# Lets the probe call allowlisted models through the restricted range.
resource "google_project_iam_member" "probe_invoker" {
  project = local.prod
  role    = var.gemini_invoker_role
  member  = google_service_account.probe.member
}

# Bucket outside the perimeter that the egress test tries to write to.
resource "google_storage_bucket" "outside" {
  project                     = var.project_ids["nonprod"]
  name                        = "${var.project_ids["nonprod"]}-perimeter-probe"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  labels                      = merge(var.labels, { env = "nonprod", purpose = "perimeter-probe" })

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }
}

# Gives the probe write access so a refusal can only come from the perimeter.
resource "google_storage_bucket_iam_member" "outside_writer" {
  bucket = google_storage_bucket.outside.name
  role   = "roles/storage.objectUser"
  member = google_service_account.probe.member
}

# Hello service behind the load balancer, reachable only through it and with all egress through the VPC.
resource "google_cloud_run_v2_service" "probe" {
  project             = local.prod
  location            = var.region
  name                = "platform-probe"
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  custom_audiences    = ["https://${var.hostname}"]
  deletion_protection = false
  labels              = merge(var.labels, { env = "prod" })

  template {
    service_account = google_service_account.probe.email

    scaling {
      max_instance_count = 1
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }

    vpc_access {
      egress = "ALL_TRAFFIC"
      network_interfaces {
        network    = var.network
        subnetwork = var.subnetwork
      }
    }
  }

  depends_on = [google_project_service_identity.run]
}

# Job that tries the internet, a model call, and a write outside the perimeter, and prints each result.
resource "google_cloud_run_v2_job" "egress" {
  project             = local.prod
  location            = var.region
  name                = "platform-egress-probe"
  deletion_protection = false
  labels              = merge(var.labels, { env = "prod" })

  template {
    template {
      service_account = google_service_account.probe.email
      max_retries     = 0
      timeout         = "300s"

      containers {
        image   = "gcr.io/google.com/cloudsdktool/cloud-sdk:587.0.0-slim"
        command = ["bash", "-c"]
        args = [<<-EOT
          echo "internet: $(curl -sS -m 10 -o /dev/null -w '%%{http_code}' https://www.google.com 2>&1 || true)"
          TOKEN=$(gcloud auth print-access-token)
          echo "model: $(curl -sS -m 30 -o /dev/null -w '%%{http_code}' -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"contents":[{"role":"user","parts":[{"text":"Reply OK"}]}]}' "$MODEL_URL" 2>&1 || true)"
          if echo probe | gcloud storage cp - "gs://$OUTSIDE_BUCKET/probe.txt" 2>&1; then echo "outside write: succeeded"; else echo "outside write: refused"; fi
        EOT
        ]

        env {
          name  = "MODEL_URL"
          value = local.egress_test_url
        }

        env {
          name  = "OUTSIDE_BUCKET"
          value = google_storage_bucket.outside.name
        }
      }

      vpc_access {
        egress = "ALL_TRAFFIC"
        network_interfaces {
          network    = var.network
          subnetwork = var.subnetwork
        }
      }
    }
  }

  depends_on = [google_project_service_identity.run]
}

# Serverless network endpoint group that sends load balancer traffic to the probe service.
resource "google_compute_region_network_endpoint_group" "probe" {
  project               = local.prod
  name                  = "platform-probe"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.probe.name
  }
}

# Backend for the external Application Load Balancer, with request logging.
resource "google_compute_backend_service" "probe" {
  project               = local.prod
  name                  = "platform-probe"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.probe.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# Routes every request on the prod hostname to the probe backend.
resource "google_compute_url_map" "prod" {
  project         = local.prod
  name            = "prod"
  default_service = google_compute_backend_service.probe.id
}

# Terminates TLS with the managed certificate.
resource "google_compute_target_https_proxy" "prod" {
  project          = local.prod
  name             = "prod"
  url_map          = google_compute_url_map.prod.id
  ssl_certificates = [var.certificate]
}

# Public HTTPS entry point on the reserved address.
resource "google_compute_global_forwarding_rule" "prod" {
  project               = local.prod
  name                  = "prod-https"
  target                = google_compute_target_https_proxy.prod.id
  ip_address            = var.lb_address
  ip_protocol           = "TCP"
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
