output "network" {
  value = google_compute_network.prod.id
}

output "subnetwork" {
  value = google_compute_subnetwork.prod.id
}

output "lb_address" {
  value = google_compute_global_address.lb.address
}

output "certificate" {
  value = google_compute_managed_ssl_certificate.prod.id
}

output "name_servers" {
  value = google_dns_managed_zone.prod.name_servers
}
