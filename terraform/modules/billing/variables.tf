variable "project_id" {
  type        = string
  description = "Project that holds the notification channel and the export dataset."
}

variable "folder" {
  type        = string
  description = "Folder resource name in the form folders/ID."
}

variable "billing_account" {
  type = string
}

variable "budget_amount" {
  type        = number
  description = "Monthly amount in the billing account's currency."
}

variable "alert_email" {
  type = string
}

variable "dataset_location" {
  type    = string
  default = "US"
}

variable "labels" {
  type = map(string)
}
