variable "project_id" {
  type = string
}

variable "project_number" {
  type = string
}

variable "region" {
  type = string
}

variable "state_bucket" {
  type = string
}

variable "terraform_service_account" {
  type        = string
  description = "Resource ID of the apply service account."
}

variable "terraform_plan_service_account" {
  type        = string
  description = "Resource ID of the read-only plan service account."
}

variable "platform_repo_uri" {
  type = string
}

variable "github_connection_name" {
  type = string
}

variable "github_connection_authorized" {
  type = bool
}

variable "github_app_installation_id" {
  type = number
}

variable "github_oauth_token_secret_version" {
  type = string
}
