output "terraform" {
  value = {
    id     = google_service_account.terraform.id
    email  = google_service_account.terraform.email
    member = google_service_account.terraform.member
  }
}

output "terraform_plan" {
  value = {
    id     = google_service_account.terraform_plan.id
    email  = google_service_account.terraform_plan.email
    member = google_service_account.terraform_plan.member
  }
}
