# ADR-004: State and CI ownership

**Status:** Accepted. Describes planned behavior; nothing here is implemented or verified.

## Context

TenantLoom AI runs Terraform from Cloud Build. Before CI exists, someone has to create the projects, the state bucket, and the CI identities. Platform state owns organization policies, the folder, projects, perimeter, and catalog allowlists. Each team has its own tenant state for its slice.

Five questions follow from that:

- **Bootstrap.** The first resources must be created by a person, then handed to CI without defining anything twice.
- **Scope.** Platform state sets per-project `vertexai.allowedModels` policies from the catalog and manages the prod perimeter. The tenant module creates team budgets and Cloud Identity groups. Google documents Organization Policy Administrator as grantable only at the organization, and the access policy that holds the perimeter is an organization-level resource. A folder-scoped identity cannot do this work.
- **Pull request execution.** A pull request build runs code from the pull request. Terraform can run arbitrary programs during `plan`, for example through an external data source, so whatever identity plans a pull request is exposed to unreviewed code. Google's trigger guidance warns that a trigger's service account gives its permissions to anyone who can start a build.
- **Approval.** Changes to prod, organization policy, the perimeter, or IAM must be approved. Cloud Build approval is set per trigger, not per change, and it happens before a build starts, so an approver cannot see what that build will apply.
- **State bucket.** After bootstrap, platform state manages the bucket that stores it, in the same project where team builds run. A mistaken replacement or deletion would lose every state at once, and any identity with project-level storage access could read or change it. `roles/cloudbuild.builds.builder`, the usual role for build accounts, grants read, write, and delete on every bucket in its project.

## Decision

1. **Bootstrap migrates state instead of importing it.**
   - There is one platform Terraform root.
   - Break-glass applies it once from the admin workstation, limited to the bootstrap resources and using local state:
     - The three projects under the existing `ai-platform` folder, which is imported
     - The state bucket
     - Both CI identities and their roles
     - A temporary probe account
     - The GitHub connection
     - The platform triggers
   - The state then moves into the new bucket, and CI applies from then on.
   - Four steps happen outside Terraform:
     - Assigning Groups Admin to `sa-terraform` in the Admin console
     - Assigning a read-only groups role to `sa-terraform-plan` in the Admin console
     - Authorizing the GitHub connection in the console, which also creates its token secret
     - Setting the branch ruleset on `main` in GitHub
2. **`sa-terraform` applies.** Only the merge-time platform triggers run as `sa-terraform`. No person holds standing permission to act as it. Folder grants reach only the three projects.

   | Scope | Roles | Used for |
   |---|---|---|
   | Organization | `roles/orgpolicy.policyAdmin` | Organization, folder, and project policies, including catalog allowlists |
   | Organization | `roles/accesscontextmanager.policyAdmin` | Access policy and prod perimeter |
   | Billing account | `roles/billing.costsManager` | Team and project budgets |
   | Billing account | `roles/billing.user` | Project billing links |
   | Cloud Identity | Groups Admin, assigned manually | Team groups |
   | `ai-platform` folder | `roles/resourcemanager.folderIamAdmin` | Folder IAM and Data Access audit configuration |
   | `ai-platform` folder | `roles/logging.admin` | Folder sink, log buckets, team log views |
   | `ai-platform` folder | `roles/resourcemanager.projectIamAdmin` | Project IAM, including conditional `run.invoker` grants |
   | `ai-platform` folder | `roles/billing.projectManager` | Project side of billing links |
   | `ai-platform` folder | `roles/serviceusage.serviceUsageAdmin` | Enabling APIs |
   | `ai-platform` folder | `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountUser` | Creating service accounts, their IAM, and attaching them to triggers, targets, and jobs, including itself |
   | Each of the three projects | `roles/iam.roleAdmin` | The custom Gemini Invoker and plan reader roles; Google allows this role only at project level |
   | `ai-platform` folder | `roles/storage.admin` | All buckets, including the state bucket |
   | `ai-platform` folder | `roles/bigquery.dataOwner` | Datasets, per-team `eval_runs` tables, and the governance view |
   | `ai-platform` folder | `roles/monitoring.editor` | Dashboards, alerts, and notification channels |
   | `ai-platform` folder | `roles/cloudbuild.builds.editor`, `roles/cloudbuild.connectionAdmin` | Triggers, the GitHub connection, and repositories |
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

3. **`sa-terraform-plan` plans pull requests.** It plans without taking the state lock, and has no write access, no secret access, and no permission to act as another identity.

   | Scope | Roles |
   |---|---|
   | Organization | `roles/orgpolicy.policyViewer`, `roles/accesscontextmanager.policyReader` |
   | Billing account | `roles/billing.viewer` |
   | Cloud Identity | A read-only groups admin role, assigned manually |
   | `ai-platform` folder | `roles/iam.securityReviewer`, `roles/modelarmor.floorSettingsViewer`, `roles/privilegedaccessmanager.viewer`, `roles/cloudquotas.viewer`, `roles/cloudbuild.connectionViewer` |
   | Each of the three projects | A custom plan reader role holding the get and list permissions Terraform needs, without `bigquery.jobs.create`, any job or workload creation, or log-entry reads |
   | State bucket | `roles/storage.objectViewer` |

   Basic Viewer is not used, because it lets a principal start BigQuery jobs. The custom role is created during bootstrap and refined from the first pull request plans.

4. **Pull request builds are limited.** Pull request builds run only for repository collaborators. CODEOWNERS assigns the whole repository, including `cloudbuild/` and the CODEOWNERS file, to `ai-governance`, and a branch ruleset on `main` requires a pull request and code owner approval, with no bypass. The merge-time build runs repository code as `sa-terraform` before the apply approval, so every merged change must already have been reviewed. No configuration uses a data source that reads secret values, so state never contains secrets and a plan never needs secret access.
5. **Every platform and tenant apply waits for approval.**
   - On merge, a build running as `sa-terraform` saves the plan and shows it.
   - A separate apply build waits for Cloud Build approval from `ai-governance`, then applies exactly that saved plan. The apply build fails if no saved plan exists for its commit.
   - Terraform rejects a saved plan if the state changed after it was made.
   - The GCS backend's built-in locking serializes applies.
6. **Platform state manages the state bucket, with protection.** The bucket has `prevent_destroy`, object versioning with a retention period for noncurrent versions, and soft delete. Saved plans live under a `plans/` prefix in the same bucket. Only `sa-terraform` can write it, and break-glass recovers it.
7. **Team identities get no project-level storage roles.**
   - Team build accounts get these roles, and never `roles/cloudbuild.builds.builder`:
     - `roles/logging.logWriter`
     - Artifact Registry writer on their own repository
     - Cloud Deploy releaser on their own pipeline
     - `actAs` on their deploy accounts
     - Object access on Cloud Deploy's artifact bucket only
   - `run.invoker` for team callers is granted at project level with a condition on service names that start with `<id>-`, so prod service names start with the team ID.
8. **CI identities reach prod through perimeter ingress rules.** Both identities run in Cloud Build outside the prod perimeter, and IAM roles do not get past VPC Service Controls. Ingress rules admit:
   - `sa-terraform` for all restricted services.
   - `sa-terraform-plan` for read methods, where a service supports method limits.
   - The break-glass account, for recovery.

## Consequences

- **The role list records intent, not a hard limit.** Project IAM Admin lets `sa-terraform` grant itself any role in the three projects, so in practice it is as powerful as Owner there. The controls are:
  - Approval on every apply.
  - CODEOWNERS.
  - The monthly access review, which flags any grant to `sa-terraform` not listed here.
- **Approver groups are reachable.** Groups Admin lets `sa-terraform` change any group, including `ai-governance` and `auditors`, so a malicious change could add its own approver. Mitigations:
  - CODEOWNERS covers the whole repository.
  - Every apply needs `ai-governance` approval.
  - Any membership change to either group raises an alert.
- **Pull request code can read what the plan identity reads.** That includes Terraform state, the configuration of the folder and projects, and budgets on the billing account. Keeping secrets out of state and limiting pull request builds to collaborators keeps this exposure to read access only.
- **Wider billing visibility.** The billing account also pays for projects outside TenantLoom AI, so both CI identities can see their budgets. A dedicated billing account would remove this; the lab does not use one.
- **Team build accounts need care.** Cloud Build's usual build role would expose the state bucket, so every team build account needs the scoped roles above, and the probe test guards against a regression.
- **More approvals.** Routine tenant changes also wait for `ai-governance`. At two teams the extra approvals are small.
- **Recovery needs break-glass.** No standing human access to state means recovering a damaged state requires break-glass.
- **Drift is visible.** The weekly drift check covers the state bucket's own configuration, so changes to it show up.

## Alternatives considered

- **A separate bootstrap root with import blocks.** Rejected. Every bootstrap resource would be defined twice, and rerunning the bootstrap root with stale local state would conflict with CI-managed state.
- **One identity for pull request plans and applies.** Rejected. Unreviewed pull request code would run with organization policy, perimeter, and Groups Admin privileges before any approval.
- **No cloud credentials on pull requests.** Rejected. It is the safest option, but reviewers would merge without seeing a plan, and a plan rejected at approval would leave unapplied code on `main` that has to be reverted.
- **Owner on the three projects.** Not chosen. It is no more powerful in practice than the list above, but it hides which services the platform manages and includes access to secret values.
- **Folder-scoped `sa-terraform` with policies applied by an administrator.** Rejected. Catalog allowlists change with every model addition and retirement and would need the same organization-level role anyway.
- **CODEOWNERS on selected paths.** Rejected. Build configuration, scripts, and the CODEOWNERS file itself would fall outside review, and the merge-time build runs them as `sa-terraform`.
- **Approval only on triggers for sensitive paths.** Rejected. The tenant module creates prod IAM and budgets, so almost every change is sensitive. Path-based triggers are also fragile when all of them apply one state.
- **Approve, then plan and apply in one build.** Rejected. The approver would approve a plan they cannot see.
- **State bucket left out of Terraform.** Rejected. Drift on the bucket would go undetected, and every change to it would need break-glass.

## Verification

- **Lab checks** (architecture, section 15):
  - `sa-terraform` can set project-level organization policies with its organization grant.
  - The role lists above are complete for the first apply and the first pull request plan.
  - A conditional `run.invoker` grant limits callers to their own team's services.
  - The read-only groups role lets `sa-terraform-plan` read team groups.
  - With the perimeter enforced, plans and applies against prod resources succeed through the management ingress rules, and break-glass recovery access works.
  - Cloud Identity Free can share its audit logs so a membership change to either approver group raises an alert. Fallback: a scheduled membership comparison.
- **Evidence to collect:**
  - `sa-probe-build` is denied read and write on the state bucket. The probe is deleted afterward.
  - A pull request build cannot write state, take the lock, act as `sa-terraform`, or create BigQuery or Cloud Run jobs.
  - A pull request that changes only `cloudbuild/` or the CODEOWNERS file cannot merge without `ai-governance` approval.
  - An apply runs only after approval.
  - A saved plan made stale by another apply is rejected.
  - A plan that would destroy the state bucket fails.
