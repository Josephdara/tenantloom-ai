variable "project_id" {
  type        = string
  description = "Prod project ID."
}

variable "region" {
  type = string
}

variable "hostname" {
  type        = string
  description = "DNS name served by the prod load balancer."
}

variable "labels" {
  type = map(string)
}
