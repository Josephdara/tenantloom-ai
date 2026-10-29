# Inputs for the platform layer. CI loads the IDs from the config file that bootstrap publishes.

variable "org_id" {
  type = string
}

variable "billing_account" {
  type = string
}

variable "platform_folder_id" {
  type = string
}

variable "project_prefix" {
  type    = string
  default = "jd-aip-"
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "bq_location" {
  type    = string
  default = "US"
}
