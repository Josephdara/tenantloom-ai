# Inputs for the organization, billing account, region, groups, and GitHub connection.

variable "org_id" {
  type        = string
  description = "Numeric organization ID."
}

variable "billing_account" {
  type        = string
  description = "Billing account ID in the form XXXXXX-XXXXXX-XXXXXX."
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "bq_location" {
  type        = string
  default     = "US"
  description = "BigQuery location shared by every platform dataset."
}

variable "project_prefix" {
  type    = string
  default = "jd-aip-"
}

variable "quota_project" {
  type    = string
  default = null
}

variable "platform_admins_group" {
  type = string
}

variable "governance_group" {
  type = string
}

variable "auditors_group" {
  type = string
}

variable "github_connection_name" {
  type    = string
  default = "github"
}

variable "github_app_installation_id" {
  type = number
}

variable "github_oauth_token_secret_version" {
  type        = string
  description = "Secret Manager version the console created for the connection, in the form projects/P/secrets/S/versions/V."
}

variable "platform_repo_uri" {
  type        = string
  description = "HTTPS clone URI of the tenantloom-ai repository."
}
