# Bootstrap state, stored in the platform state bucket this layer creates.

terraform {
  backend "gcs" {
    bucket = "jd-aip-bootstrap-platform-state"
    prefix = "bootstrap"
  }
}
