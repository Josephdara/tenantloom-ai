# Org state in the platform state bucket; CI supplies the bucket and prefix at init.

terraform {
  backend "gcs" {}
}
