variable "org_id" {
  type = string
}

variable "billing_account" {
  type = string
}

variable "folder" {
  type        = string
  description = "Folder resource name in the form folders/ID."
}

variable "project_ids" {
  type        = map(string)
  description = "Platform project IDs keyed by environment, including nonprod."
}

variable "governance_group" {
  type = string
}
