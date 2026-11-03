# ADR-004: State and CI ownership

**Status:** Accepted. The decisions below are implemented for the platform root. Verified results and open items are in [foundation evidence](../evidence/foundation.md); the membership alert is not yet verified.

## Context

TenantLoom AI runs Terraform from Cloud Build. Before CI exists, someone has to create the projects, the state bucket, and the CI identities. Platform state owns organization policies, the folder, projects, perimeter, and catalog allowlists. Each team has its own tenant state for its slice.

Five questions follow from that:

- **Bootstrap.** The first resources must be created by a person, then handed to CI without defining anything twice.
- **Scope.** Platform state sets per-project `vertexai.allowedModels` policies from the catalog and manages the prod perimeter. Google documents Organization Policy Administrator as grantable only at the organization, and the access policy that holds the perimeter is an organization-level resource. A folder-scoped identity cannot do this work.
- **Pull request execution.** A pull request build runs code from the pull request. Terraform can run arbitrary programs during `plan`, for example through an external data source, so whatever identity plans a pull request is exposed to unreviewed code. Google's trigger guidance warns that a trigger's service account gives its permissions to anyone who can start a build.
- **Approval.** Changes to prod, organization policy, the perimeter, or IAM must be approved. Cloud Build approval is set per trigger, not per change, and it happens before a build starts.
- **State bucket.** After bootstrap, platform state manages the bucket that stores it, in the same project where team builds run. A mistaken replacement or deletion would lose every state at once, and any identity with project-level storage access could read or change it. `roles/cloudbuild.builds.builder`, the usual role for build accounts, grants read, write, and delete on every bucket in its project.

## Decision

1. **Bootstrap migrates state instead of importing it.**
   - There is one platform Terraform root.
   - Break-glass applies it from the admin workstation with local state, limited to the bootstrap resources, in two passes:
     - **Pass 1:** the three projects under the existing `ai-platform` folder, which is imported; the state bucket; both CI identities and their roles; a temporary probe account; and the Cloud Build service agent's Secret Manager grant.
     - **Between passes:** the GitHub connection is created with gcloud and authorized in the browser, which installs the Google Cloud Build GitHub App on this repository and stores its token in Secret Manager. Terraform cannot create the connection itself, because the provider omits an empty GitHub configuration and the Cloud Build API rejects a connection without one.
     - **Pass 2:** imports the connection and creates the repository link and the three platform triggers.
   - The state then moves into the new bucket before the first pull request, so the first CI plan reads real state. CI applies from then on.
   - Break-glass then removes the Owner role Google grants a project's creator on each of the three projects, and the temporary Project Creator role on the folder.
2. **`sa-terraform` applies.** Only the merge-time platform triggers run as `sa-terraform`. No person holds standing permission to act as it. Folder grants reach only the three projects.

   | Scope | Roles | Used for |
   |---|---|---|
   | Organization | `roles/orgpolicy.policyAdmin` | Organization, folder, and project policies, including catalog allowlists |
   | Organization | `roles/accesscontextmanager.policyAdmin` | Access policy and prod perimeter |
   | Organization | `roles/iam.organizationRoleViewer` | Reading its own organization-level grants during plans |
   | Billing account | `roles/billing.costsManager` | Team and project budgets |
   | Billing account | `roles/billing.user` | Project billing links |
   | `ai-platform` folder | `roles/resourcemanager.folderIamAdmin` | Folder IAM and Data Access audit configuration |
   | `ai-platform` folder | `roles/logging.admin` | Folder sink, log buckets, log views, team log views |
   | `ai-platform` folder | `roles/resourcemanager.projectIamAdmin` | Project IAM, including conditional `run.invoker` grants |
   | `ai-platform` folder | `roles/billing.projectManager` | Project side of billing links |
   | `ai-platform` folder | `roles/serviceusage.serviceUsageAdmin` | Enabling APIs |
   | `ai-platform` folder | `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountUser` | Creating service accounts, their IAM, and attaching them to triggers, targets, and jobs, including itself |
   | Each of the three projects | `roles/iam.roleAdmin` | The custom Gemini Invoker and plan reader roles; Google allows this role only at project level |
   | `ai-platform` folder | `roles/storage.admin` | All buckets, including the state bucket |
   | `ai-platform` folder | `roles/bigquery.dataOwner` | Datasets, per-team `eval_runs` tables, and the governance view |
   | `ai-platform` folder | `roles/monitoring.editor` | Dashboards, alerts, and notification channels |
   | `ai-platform` folder | `roles/cloudbuild.builds.editor`, `roles/cloudbuild.connectionAdmin` | Triggers, the GitHub connection, repositories, and starting the apply build |
   | `ai-platform` folder | `roles/clouddeploy.admin` | Pipelines, targets, and repair rules |
   | `ai-platform` folder | `roles/artifactregistry.admin` | Repositories and their IAM |
   | `ai-platform` folder | `roles/binaryauthorization.attestorsAdmin`, `roles/binaryauthorization.policyEditor` | The attestor and the prod policy |
   | `ai-platform` folder | `roles/containeranalysis.admin` | The attestation note and its IAM |
   | `ai-platform` folder | `roles/cloudkms.admin` | Key rings, keys, and key IAM, without the ability to use keys |
   | `ai-platform` folder | `roles/modelarmor.floorSettingsAdmin` | Model Armor floor settings |
   | `ai-platform` folder | `roles/privilegedaccessmanager.admin` | PAM entitlements |
   | `ai-platform` folder | `roles/run.developer` | Team eval jobs |
   | `ai-platform` folder | `roles/cloudscheduler.admin` | Daily canary and drift schedules |
   | `ai-platform` folder | `roles/compute.networkAdmin`, `roles/compute.securityAdmin` | VPC, load balancer and serverless network endpoint groups; firewall rules and certificates |
   | `ai-platform` folder | `roles/dns.admin` | DNS response policy |
   | `ai-platform` folder | `roles/cloudquotas.admin` | Agent Platform quota limits |

   `sa-terraform` holds no `setIamPolicy` permission on the organization or the billing account, so it can read but not change its own organization-level and billing grants. Changing them needs break-glass.

3. **`sa-terraform-plan` plans pull requests.** It plans without taking the state lock, and has no write access to state, no secret access, and no permission to act as another identity.

   | Scope | Roles |
   |---|---|
   | Organization | `roles/orgpolicy.policyViewer`, `roles/accesscontextmanager.policyReader`, `roles/iam.organizationRoleViewer` |
   | Billing account | `roles/billing.viewer` |
   | `ai-platform` folder | `roles/iam.securityReviewer`, `roles/resourcemanager.folderViewer`, `roles/modelarmor.floorSettingsViewer`, `roles/privilegedaccessmanager.viewer`, `roles/cloudquotas.viewer`, `roles/cloudbuild.connectionViewer`, and the organization custom role `terraformLogConfigReader` |
   | Each of the three projects | A custom plan reader role holding the get and list permissions Terraform needs, without `bigquery.jobs.create`, any job or workload creation, log-entry reads, or secret access |
   | `jd-aip-nonprod` | `roles/logging.logWriter`, so its builds can write their own logs |
   | State bucket | `roles/storage.objectViewer` |

   No predefined role reads log sinks without also reading log entries, so `terraformLogConfigReader` holds only `logging.sinks.get` and `logging.sinks.list`. It is an organization role, which `sa-terraform` cannot create, so break-glass created it outside Terraform; Terraform grants it on the folder.

   Basic Viewer is not used, because it lets a principal start BigQuery jobs. The custom role grows with each new resource type, and each pull request plan shows whether it is complete.

4. **Pull request builds are limited.**
   - Pull request builds run only for repository collaborators; outside contributors need a collaborator comment.
   - CODEOWNERS assigns the whole repository, including `cloudbuild/` and the CODEOWNERS file, to the code owner.
   - A branch ruleset on `main` requires a pull request, the platform plan check, code owner approval, approval of the latest push, and resolved review threads.
   - The repository has a single maintainer, who cannot approve their own pull requests. Repository administrators may therefore bypass the ruleset, but only through a pull request; direct pushes to `main` stay blocked, and GitHub records each bypass.
   - No configuration uses a data source that reads secret values, so state never contains secrets and a plan never needs secret access.
5. **Every platform and tenant change waits for two approvals.**
   - On merge, a build running as `sa-terraform` waits for Cloud Build approval from `ai-governance`, then plans, saves the plan under `plans/<commit>.tfplan`, and starts the apply trigger for the same commit.
   - The apply trigger has no repository event. Only the merge plan build starts it, so an apply build exists only after a saved plan does. It waits for a second approval, then applies exactly that saved plan, and fails if none exists.
   - The first approval keeps repository code from running as `sa-terraform` before a Google identity has approved it. This matters because the maintainer can bypass code review.
   - Terraform rejects a saved plan if the state changed after it was made, and the GCS backend's built-in locking serializes applies.
   - Approvers read plan and apply output through a log view limited to Cloud Build logs. `ai-governance` holds `roles/cloudbuild.builds.approver` in nonprod and `roles/logging.viewAccessor` on that view only, so approvers see every plan they approve without reading any other logs.
6. **Platform state manages the state bucket, with protection.**
   - The bucket has `prevent_destroy`, object versioning with noncurrent versions kept for 30 days, and soft delete.
   - Saved plans live under a `plans/` prefix and are deleted after 30 days.
   - The bucket also holds `config/platform.auto.tfvars.json`, the root module inputs that CI loads at build time. It keeps the organization ID, billing account, and budget alert address out of the repository. Terraform writes it from the same inputs, so adding a new private input means writing the key into the object once with break-glass before the change that uses it; the [bootstrap runbook](../runbooks/bootstrap.md) covers this.
   - Only `sa-terraform` writes state, `sa-terraform-plan` reads it, and break-glass recovers it by granting itself access through its organization roles.
7. **Team identities get no project-level storage roles.**
   - Team build accounts get these roles, and never `roles/cloudbuild.builds.builder`:
     - `roles/logging.logWriter`
     - Artifact Registry writer on their own repository
     - Cloud Deploy releaser on their own pipeline
     - `actAs` on their deploy accounts
     - Object access on Cloud Deploy's artifact bucket only
   - `run.invoker` for team callers is granted at project level with a condition on service names that start with `<id>-`, so prod service names start with the team ID.
8. **Terraform manages no Cloud Identity groups.** An administrator creates every group, including `ai-governance`, `auditors`, `platform-admins`, and each team's `<id>-developers` and `<id>-release-approvers`, and manages their membership in the Admin console. Terraform only grants IAM to groups by address. Neither CI identity holds a Cloud Identity admin role.
9. **CI identities reach prod through perimeter ingress rules.** Both identities run in Cloud Build outside the prod perimeter, and IAM roles do not get past VPC Service Controls. Ingress rules admit:
   - `sa-terraform` for all restricted services.
   - `sa-terraform-plan` for read methods, where a service supports method limits.
   - The break-glass account, for recovery.

## Accepted exceptions

These differ from the decisions above and are kept deliberately. The monthly access review checks both.

- **Legacy Cloud Build service account.** Google granted `PROJECT_NUMBER@cloudbuild.gserviceaccount.com` `roles/cloudbuild.builds.builder` in `jd-aip-nonprod` when the Cloud Build API was enabled. That role can read and write the state bucket. Every trigger names its own service account, so no build runs as this account; a build that did would show it in the audit logs.
- **Inherited folder administrator.** One named administrator account holds Folder Admin and Folder Editor on `ai-platform`, which every project inherits, including prod. It can grant itself any role there, so prod has standing human access through this account. Audit logs and the access review are the controls.

## Consequences

- **The role list records intent, not a hard limit.** Project IAM Admin lets `sa-terraform` grant itself any role in the three projects, so in practice it is as powerful as Owner there. The controls are the two approvals on every change, CODEOWNERS, and the monthly access review, which flags any grant to `sa-terraform` not listed here.
- **Approver groups are out of CI's reach.** Because Terraform manages no groups, a merged change cannot add its own approver. Group membership changes made in the Admin console raise an alert instead.
- **Onboarding has a manual first step.** An administrator creates a team's groups before its pull request. Onboarding time is measured from approval of the saved plan, so it does not include this step.
- **Review is weaker with one maintainer.** Code owner approval is bypassed on every merge. The approval before the merge plan runs, and the approval of the saved plan, are the controls that remain.
- **Pull request code can read what the plan identity reads.** That includes Terraform state, the CI configuration, the configuration of the folder and projects, organization IAM, and budgets on the billing account. Keeping secrets out of state and limiting pull request builds to collaborators keeps this exposure to read access only.
- **Wider billing and organization visibility.** The billing account also pays for projects outside TenantLoom AI, so both CI identities can see their budgets. Organization Role Viewer lets both read project IAM across the organization.
- **More approvals.** Every change, including documentation-only changes, needs two approvals. At two teams the extra approvals are small.
- **Recovery needs break-glass.** No person has standing access to state. Break-glass sessions also require recent re-authentication, so each break-glass task starts with a fresh sign-in.
- **Drift is visible.** The weekly drift check covers the state bucket's own configuration, so changes to it show up.

## Alternatives considered

- **A separate bootstrap root with import blocks.** Rejected. Every bootstrap resource would be defined twice, and rerunning the bootstrap root with stale local state would conflict with CI-managed state.
- **One identity for pull request plans and applies.** Rejected. Unreviewed pull request code would run with organization policy and perimeter privileges before any approval.
- **No cloud credentials on pull requests.** Rejected. It is the safest option, but reviewers would merge without seeing a plan, and a plan rejected at approval would leave unapplied code on `main` that has to be reverted.
- **Owner on the three projects.** Not chosen. It is no more powerful in practice than the list above, but it hides which services the platform manages and includes access to secret values.
- **Folder-scoped `sa-terraform` with policies applied by an administrator.** Rejected. Catalog allowlists change with every model addition and retirement and would need the same organization-level role anyway.
- **CODEOWNERS on selected paths.** Rejected. Build configuration, scripts, and the CODEOWNERS file itself would fall outside review, and the merge-time build runs them as `sa-terraform`.
- **Approval only on the apply.** Rejected for a single-maintainer repository. The merge plan would run code that nobody else reviewed as `sa-terraform` before any approval.
- **Approve, then plan and apply in one build.** Rejected. The approver would approve a plan they cannot see.
- **Terraform-managed groups with Groups Admin for `sa-terraform`.** Rejected. Groups Admin reaches every group in the directory, including `ai-governance`, so a merged change could add its own approver.
- **A conditional project-level grant for log access.** Replaced by a grant on the log view itself, which Google recommends and which needs no IAM condition.
- **State bucket left out of Terraform.** Rejected. Drift on the bucket would go undetected, and every change to it would need break-glass.

## Verification

- **Lab checks** (architecture, section 15):
  - `sa-terraform` can set project-level organization policies with its organization grant.
  - The role lists above are complete for each new resource type: every pull request plan and merge plan refreshes all resources without permission errors.
  - A conditional `run.invoker` grant limits callers to their own team's services.
  - With the perimeter enforced, plans and applies against prod resources succeed through the management ingress rules, and break-glass recovery access works.
  - Cloud Identity Free can share its audit logs so a membership change to either approver group raises an alert. Fallback: a scheduled membership comparison.
- **Evidence:** results for the probe, pull request build denials, the ruleset, approvals, and the log view are in [foundation evidence](../evidence/foundation.md).
