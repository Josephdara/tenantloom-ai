variable "folder" {
  type        = string
  description = "Folder resource name in the form folders/ID."
}

variable "project_ids" {
  type        = map(string)
  description = "Platform project IDs keyed by environment."
}

variable "region" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "governance_group" {
  type        = string
  description = "Email of the approver group, which receives governance alerts."
}

variable "auditors_group" {
  type        = string
  description = "Email of the group that reads audit and prompt logs."
}
