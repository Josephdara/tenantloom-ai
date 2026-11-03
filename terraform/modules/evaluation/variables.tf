variable "project_id" {
  type        = string
  description = "Sandbox project ID, which hosts catalog evaluation."
}

variable "nonprod_project_id" {
  type        = string
  description = "Nonprod project ID, which holds held-out data."
}

variable "region" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "gemini_invoker_role" {
  type        = string
  description = "Gemini Invoker custom role in the sandbox project."
}

variable "platform_admins_group" {
  type        = string
  description = "Email of the group that uploads datasets and deploys sandbox models."
}

variable "governance_group" {
  type        = string
  description = "Email of the group that reviews evaluation results."
}
