variable "project_ids" {
  type        = map(string)
  description = "Platform project IDs keyed by environment."
}

variable "region" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "hostname" {
  type        = string
  description = "DNS name served by the prod load balancer."
}

variable "network" {
  type        = string
  description = "Prod VPC resource ID."
}

variable "subnetwork" {
  type        = string
  description = "Prod subnet resource ID for Direct VPC egress."
}

variable "lb_address" {
  type        = string
  description = "Reserved global address for the load balancer."
}

variable "certificate" {
  type        = string
  description = "Managed certificate resource ID."
}

variable "gemini_invoker_role" {
  type        = string
  description = "Prod Gemini Invoker custom role name."
}

variable "model" {
  type        = string
  description = "Allowlisted prod model the egress test calls."
}
