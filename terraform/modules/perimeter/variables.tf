variable "org_id" {
  type        = string
  description = "Numeric organization ID."
}

variable "prod_project_number" {
  type = string
}

variable "nonprod_project_number" {
  type = string
}

variable "terraform_service_account" {
  type        = string
  description = "Email of the apply service account."
}

variable "terraform_plan_service_account" {
  type        = string
  description = "Email of the read-only plan service account."
}

variable "breakglass_account" {
  type        = string
  description = "Email of the break-glass administrator account."
}

variable "platform_admins_group" {
  type = string
}

variable "audit_sink_writer" {
  type        = string
  description = "Writer identity of the folder audit sink, with its member prefix."
}
