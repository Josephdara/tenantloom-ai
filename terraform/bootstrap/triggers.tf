# Pull request plan, main plan, and approval-gated apply triggers for each CI layer.

locals {
  trigger_substitutions = {
    for k, l in local.ci_layers : k => {
      _LAYER        = k
      _TF_DIR       = l.dir
      _STATE_BUCKET = local.state_buckets[l.state_bucket]
      _STATE_PREFIX = l.state_prefix
      _PLAN_BUCKET  = local.plan_bucket
      _LOCK_BUCKET  = local.lock_bucket
    }
  }
}

resource "google_cloudbuild_trigger" "pr_plan" {
  for_each        = local.ci_layers
  project         = google_project.bootstrap.project_id
  location        = var.region
  name            = "pr-plan-${each.key}"
  service_account = google_service_account.plan[each.value.plan].id
  filename        = "cloudbuild/pr-plan.yaml"
  included_files  = ["${each.value.dir}/**", "cloudbuild/**"]
  substitutions   = local.trigger_substitutions[each.key]

  repository_event_config {
    repository = google_cloudbuildv2_repository.platform.id

    pull_request {
      branch = "^main$"
      # The repository is public, so fork pull requests build only after a collaborator comments /gcbrun.
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }
}

resource "google_cloudbuild_trigger" "main_plan" {
  for_each        = local.ci_layers
  project         = google_project.bootstrap.project_id
  location        = var.region
  name            = "main-plan-${each.key}"
  service_account = google_service_account.plan[each.value.plan].id
  filename        = "cloudbuild/plan.yaml"
  included_files  = ["${each.value.dir}/**"]
  substitutions   = local.trigger_substitutions[each.key]

  repository_event_config {
    repository = google_cloudbuildv2_repository.platform.id

    push {
      branch = "^main$"
    }
  }
}

resource "google_cloudbuild_trigger" "apply" {
  for_each        = local.ci_layers
  project         = google_project.bootstrap.project_id
  location        = var.region
  name            = "apply-${each.key}"
  service_account = google_service_account.apply[each.value.apply].id
  filename        = "cloudbuild/apply.yaml"
  included_files  = ["${each.value.dir}/**"]
  substitutions = merge(local.trigger_substitutions[each.key], {
    _PLAN_TRIGGER_ID = google_cloudbuild_trigger.main_plan[each.key].trigger_id
  })

  repository_event_config {
    repository = google_cloudbuildv2_repository.platform.id

    push {
      branch = "^main$"
    }
  }

  approval_config {
    approval_required = true
  }
}
