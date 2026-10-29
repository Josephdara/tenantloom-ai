# Inputs for the platform layer. CI loads the IDs from the config file that bootstrap publishes.

variable "org_id" {
  type        = string
  description = "Numeric organization ID, the parent of the access policy."
}

variable "billing_account" {
  type        = string
  description = "Billing account linked to the shared projects."
}

variable "platform_folder_id" {
  type        = string
  description = "Numeric ID of the platform folder that holds the shared projects."
}

variable "footprint" {
  type        = string
  default     = "full"
  description = "full: separate ops, eval, and kms projects. lab: eval and kms contents live in ops, for billing accounts that can link only a few projects."

  validation {
    condition     = contains(["full", "lab"], var.footprint)
    error_message = "footprint must be full or lab."
  }
}

variable "project_prefix" {
  type        = string
  default     = "jd-aip-"
  description = "Prefix for project IDs; also locates the CI identities in the bootstrap project."
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
