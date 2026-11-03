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

output "prod_name_servers" {
  value = module.network.name_servers
}

output "prod_lb_address" {
  value = module.network.lb_address
}

output "github_connection" {
  value = module.cloudbuild.connection
}

output "evaluation" {
  value = {
    catalog_eval_service_account = module.evaluation.catalog_eval_service_account
    model_deploy_service_account = module.evaluation.model_deploy_service_account
    buckets                      = module.evaluation.buckets
    eval_runs_table              = module.evaluation.eval_runs_table
    platform_repository          = module.cloudbuild.platform_repository
  }
}
