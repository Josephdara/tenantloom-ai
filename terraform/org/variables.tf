# Inputs for the org layer. CI loads the IDs from the config file that bootstrap publishes.

variable "org_id" {
  type = string
}

variable "ai_platform_folder_id" {
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
