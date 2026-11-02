variable "org_id" {
  type        = string
  description = "Numeric organization ID."
}

variable "billing_account" {
  type        = string
  description = "Billing account ID in the form XXXXXX-XXXXXX-XXXXXX."
}

variable "folder_id" {
  type        = string
  description = "Numeric ID of the existing ai-platform folder."
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "project_prefix" {
  type    = string
  default = "jd-aip-"
}

variable "quota_project" {
  type        = string
  default     = null
  description = "Project billed for API calls made with user credentials."
}

variable "governance_group" {
  type        = string
  description = "Email of the group that approves platform plan and apply builds."
}

variable "platform_repo_uri" {
  type        = string
  description = "HTTPS clone URI of this repository."
}

variable "github_connection_name" {
  type    = string
  default = "github"
}

variable "github_connection_authorized" {
  type        = bool
  default     = false
  description = "Whether the GitHub connection has been authorized, which the repository link and triggers require."

  validation {
    condition     = !var.github_connection_authorized || (var.github_app_installation_id != null && var.github_oauth_token_secret_version != null)
    error_message = "An authorized connection needs github_app_installation_id and github_oauth_token_secret_version."
  }
}

variable "github_app_installation_id" {
  type    = number
  default = null
}

variable "github_oauth_token_secret_version" {
  type        = string
  default     = null
  description = "Secret Manager version created when the connection was authorized, in the form projects/P/secrets/S/versions/V."
}
