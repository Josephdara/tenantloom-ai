output "project_numbers" {
  value = module.projects.project_numbers
}

output "state_bucket" {
  value = module.state.bucket
}

output "terraform_service_account" {
  value = module.ci_identities.terraform.email
}

output "terraform_plan_service_account" {
  value = module.ci_identities.terraform_plan.email
}

output "probe_build_service_account" {
  value = google_service_account.probe_build.email
}

output "github_connection" {
  value = module.cloudbuild.connection
}
