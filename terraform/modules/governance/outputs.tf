output "gemini_invoker_roles" {
  value = { for env, r in google_project_iam_custom_role.gemini_invoker : env => r.name }
}

output "prod_models" {
  value = [for m in local.catalog.models : m.id if contains(m.environments, "prod")]
}
