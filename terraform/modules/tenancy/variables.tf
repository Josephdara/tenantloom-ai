variable "project_id" {
  type        = string
  description = "Nonprod project ID, which hosts team evaluation."
}

variable "region" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "eval_runner_permissions" {
  type        = list(string)
  description = "Permissions of the catalog evaluation runner role, reused for team evaluation accounts."
}
