variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "plan_reader_member" {
  type        = string
  description = "IAM member that reads state for pull request plans."
}

variable "ci_config" {
  type        = any
  description = "Root module inputs that CI builds load as a variables file."
}
