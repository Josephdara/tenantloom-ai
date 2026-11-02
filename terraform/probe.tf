# Holds the project-level roles a team build account gets, to show they grant no access to state.
resource "google_service_account" "probe_build" {
  project      = module.projects.project_ids["nonprod"]
  account_id   = "sa-probe-build"
  display_name = "Team build access probe"
}

# Lets probe builds write logs, the only project-level role a team build account holds.
resource "google_project_iam_member" "probe_build_log_writer" {
  project = module.projects.project_ids["nonprod"]
  role    = "roles/logging.logWriter"
  member  = google_service_account.probe_build.member
}
