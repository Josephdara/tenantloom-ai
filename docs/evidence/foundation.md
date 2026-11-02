# Foundation evidence

This records what was checked on the live TenantLoom AI foundation, what was observed, and the limits of each result. The foundation is the platform Terraform root, its state bucket, the CI identities, and the Cloud Build pipeline described in [architecture section 5](../../architecture.md#5-platform-foundation) and [ADR-004](../adr/ADR-004-state-and-ci-ownership.md).

Build IDs refer to Cloud Build builds in the nonprod project, region `us-east4`. Their logs are readable by `ai-governance` through the `cloudbuild` log view.

## Summary

| Check | Lab check | Result |
|---|---|---|
| Bootstrap created the foundation and CI owns it | | Verified |
| State lives in the bucket, and the first CI plans show no changes | | Verified |
| CI role lists are complete for current resources | 9 | Verified for current resource types |
| A team-level build identity is denied the state bucket | 12 | Verified, with a limitation |
| Pull request builds cannot write state, lock it, act as `sa-terraform`, or create jobs | | Verified, with limitations |
| A plan that would destroy the state bucket fails | | Verified |
| A pull request touching only `cloudbuild/` cannot merge without code owner approval | 15 | Partly met: an administrator can bypass |
| Applies run only after `ai-governance` approval | | Verified |
| Approvers can read the plans they approve | | Verified |
| No person holds standing access to state | | Verified, with accepted exceptions |
| Platform budget exists | | Verified from the apply log only |
| A stale saved plan is rejected | | Pending |
| Billing export reaches the dataset | | Pending: not enabled |
| Cloud Run job creation is denied to pull request builds | | Pending: Cloud Run API not yet enabled |
| Groups reader | 11 | Not applicable: Terraform manages no groups |

## Details

### Bootstrap and handover to CI

- **Checked:** two local applies by the break-glass account, the GitHub connection created and authorized between them, then migration of local state into `gs://<nonprod>-tfstate/platform/`.
- **Observed:** pass 1 imported the `ai-platform` folder with no changes and created every bootstrap resource except the GitHub connection, which the Cloud Build API rejected without GitHub settings. After the connection was created with gcloud and authorized, pass 2 imported it with no changes and added the repository link and three triggers. The migrated state held 84 resource instances with the same lineage as the local state, and a plan against it reported no changes.
- **Significance:** the bootstrap resources are defined once, in the same root CI now applies.

### First CI plans

- **Checked:** the first pull request plan as `sa-terraform-plan` (build `4135c832`), then the merge plan and apply as `sa-terraform` (builds `3ba61e49` and `8daa8a74`).
- **Observed:** all three reported no changes. The merge plan saved `plans/<commit>.tfplan` and started the apply for the same commit, and the apply fetched and applied that file with nothing to change.
- **Limitation:** both approvals in this run came from the break-glass account, which still held project Owner at the time and so could approve builds. Approval evidence is from later builds, below.

### CI role lists (lab check 9)

- **Checked:** whether each CI identity can refresh every platform resource.
- **Observed:** pull request plans and merge plans refreshed all resources without permission errors, including after the budget, dataset, notification channel, and log view were added (builds `e2ad207b`, `d9b763a3`, `5b96e522`, `6922b64a`).
- **Limitation:** this covers the resource types that exist now. Each new resource type is checked again by its first plan.

### Team build identity denied state (lab check 12)

- **Checked:** a build running as `sa-probe-build`, which held only the project-level roles a team build account gets, listing, reading, and writing the state bucket (build `2043213d`).
- **Observed:** all three calls returned 403 for `storage.objects.get`, and the build succeeded only because every call was refused.
- **Limitation:** the write was refused at the read that `gcloud storage cp` makes before uploading, so `storage.objects.create` itself was not reached. The probe held no storage role, so the write would also be refused, but that was not observed directly. The probe account was removed afterward.

### Pull request build denials

- **Checked:** a pull request that changed only `cloudbuild/pr-plan.yaml`, adding steps that run as `sa-terraform-plan` (build `9d1414be`). Each step passes only if its operation fails for the named reason:
  - writing an object to the state bucket: `storage.objects.create`;
  - planning with the state lock: `Error acquiring the state lock`;
  - getting an access token as `sa-terraform`: `iam.serviceAccounts.getAccessToken`;
  - running a BigQuery query in nonprod: `bigquery.jobs.create`;
  - planning a destroy: `Instance cannot be destroyed`, from `prevent_destroy` on the state bucket.
- **Observed:** the build succeeded, so every operation was refused for its named reason. The pull request was closed without merging.
- **Limitations:** the individual log lines were not captured; the result rests on the build's pass condition. Cloud Run job creation was not tested, because the Cloud Run API is not yet enabled in nonprod.

### Merge protection (lab check 15)

- **Checked:** the same pull request, touching only `cloudbuild/`.
- **Observed:** GitHub reported it as blocked with review required, and `gh pr merge` without `--admin` failed with "the base branch policy prohibits the merge."
- **Limitation:** the repository has a single maintainer, so repository administrators may bypass the ruleset through a pull request, and every merge so far used that bypass. GitHub records each one. The check is therefore partly met: the rule blocks non-administrators, but review by a second person is not enforced.

### Approval by `ai-governance`

- **Checked:** who approved each gated build after the break-glass account lost project Owner.
- **Observed:** merge plans `d9b763a3` and `6922b64a` and applies `74781d60` and `1be0244c` were all approved by a member of `ai-governance`. The break-glass account holds no role in the nonprod project.
- **Significance:** applies run only after a Google identity outside CI approves them, both before the plan runs and before it is applied.

### Approvers can read plans

- **Checked:** an `ai-governance` member opening Logs Explorer with the `cloudbuild` log view.
- **Observed:** the log of apply build `1be0244c` was visible through the view. The view's IAM policy grants `roles/logging.viewAccessor` to `ai-governance` only.
- **Significance:** approvers see each plan before approving its apply, without access to other logs.

### Access to state

- **Checked:** project IAM in the three projects, and a read of the state bucket by the break-glass account.
- **Observed:** after bootstrap, no person holds Owner on any of the three projects, and the break-glass account was refused with 403 when reading the state bucket.
- **Accepted exceptions:** the legacy Cloud Build service account keeps `roles/cloudbuild.builds.builder` in nonprod, which can write the bucket, and one administrator account keeps Folder Admin and Folder Editor on the folder. Both are recorded in ADR-004.

### Platform budget

- **Checked:** creation of a monthly budget of 100, in the billing account's currency, for the `ai-platform` folder.
- **Observed:** the first apply failed with `Error 400` because the budget specified USD and the billing account bills in CAD. With the currency left unset, apply `1be0244c` created it.
- **Limitation:** the budget was not read back, because reading budgets with user credentials needs a quota project the break-glass account cannot use. No alert has fired yet.

## Pending

- **Stale saved plan rejected.** To be recorded with the next state-changing merges.
- **Billing export.** The `billing_export` dataset exists, but the export is not enabled.
- **Cloud Run job denial for pull request builds.** To be tested once the Cloud Run API is enabled.
- **Membership alert for `ai-governance` and `auditors` (lab check 2).** Planned with the governance work.
