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

variable "project_number" {
  type        = string
  description = "Sandbox project number, used to name its Cloud Run service agent."
}

variable "harness_image" {
  type        = string
  description = "Evaluation harness image, pinned by digest."

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.harness_image))
    error_message = "The harness image must be pinned by sha256 digest."
  }
}

variable "artifact_repository" {
  type        = string
  description = "Resource ID of the platform Artifact Registry repository."
}
