variable "folder" {
  type        = string
  description = "Folder resource name in the form folders/ID."
}

variable "org_id" {
  type        = string
  description = "Numeric organization ID."
}

variable "project_ids" {
  type        = map(string)
  description = "Platform project IDs keyed by environment."
}

variable "project_numbers" {
  type        = map(string)
  description = "Platform project numbers keyed by environment."
}

variable "platform_admins_group" {
  type        = string
  description = "Email of the group that may impersonate the model test identity."
}

variable "governance_group" {
  type        = string
  description = "Email of the group that approves temporary prod access."
}
