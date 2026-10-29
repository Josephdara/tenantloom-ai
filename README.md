# TenantLoom AI

TenantLoom AI is a governed AI platform I am building on Google Cloud. Application teams (tenants) get their own projects, model access, and budgets through pull requests, while a platform team keeps control of shared infrastructure, guardrails, and the model catalog. Every infrastructure change runs through the same path: a pull request plan, a saved plan on `main`, an approval, and a locked apply that writes an audit record.

I use it to show how an organization can offer Gemini and other Agent Platform (Vertex AI) models to many teams without giving up isolation, cost visibility, or change control. The full design is in [architecture.md](architecture.md), and the reasoning behind each major decision is in [docs/adr](docs/adr/README.md).

## Status

The foundation is implemented and running in my lab. Everything else in the architecture is still planned.

| Area | State |
|---|---|
| Bootstrap layer: CI project, state buckets, provisioning identities, saved plan and apply lock buckets, CI records dataset, `state-recovery` PAM entitlements | Implemented and applied |
| Infrastructure CI for the org layer: pull request plan, main plan, approval-gated apply with lock, hash check, and CI record | Implemented and used for every org layer change so far |
| Org layer: folders, organization policy baseline, folder grants, Data Access audit configuration | Implemented and applied through CI |
| Platform core, tenant factory, model catalog, evaluation, delivery pipeline, prod | Planned |

Observed so far: an org layer change applied only after approval, through the apply identity, from a saved plan whose hash matched; and my day-to-day admin account is denied access to Terraform state. Written evidence for these checks is still to come. Not built yet: the scheduled drift check and the alert for a stale apply lock.

## How a change flows

```text
pull request ─> pr-plan-<layer>       read-only plan, shown as a GitHub check
merge to main ─> main-plan-<layer>     saved plan + SHA-256 hash in the plan bucket
              └> apply-<layer>         waits for approval in Cloud Build
approval      ─> apply build           checks approval, takes the lock, verifies the hash,
                                       applies only that saved plan, writes a CI record,
                                       releases the lock
```

- Plans run as read-only identities. Applies run as one identity per layer (`sa-org`, `sa-platform`, `sa-factory`) and only from approved builds.
- Members of `ai-governance` approve applies. No person holds standing permission to act as an apply identity.
- Fork pull requests are configured to build only after a collaborator comments `/gcbrun`, because pull request builds read their config from the pull request.
- The bootstrap layer is the exception: it is applied locally by a break-glass administrator, because it manages the CI identities and their organization and billing roles.

## Repository layout

```text
terraform/bootstrap/   CI project, state and plan buckets, identities, triggers, CI records
terraform/org/         folders, organization and folder policies, folder grants, audit config
cloudbuild/            pull request plan, main plan, apply, and drift build configs, apply scripts
docs/adr/              architecture decision records
architecture.md        target architecture
```

## Prerequisites

- A Google Cloud organization (Cloud Identity Free is enough) and a billing account.
- Two administrator accounts: a break-glass super administrator protected by security keys, and a separate day-to-day administrator.
- Groups `ai-platform-admins`, `ai-governance`, and `auditors`, created in the Admin console. Put the approver in `ai-governance` and keep the day-to-day administrator out of it, because PAM and Cloud Build approvals should come from a different person than the requester.
- A GitHub repository holding this code.
- Terraform `1.16.4` and the Google Cloud CLI. Versions are pinned exactly, because a saved plan cannot be applied by a different Terraform or provider version.

## Values you must replace

| Value | Where |
|---|---|
| Organization ID, billing account ID, group addresses, repository URL | `terraform/bootstrap/terraform.tfvars` (copy from `terraform.tfvars.example`) |
| Project prefix `jd-aip-` | `project_prefix` in both layers' `variables.tf` |
| State bucket `jd-aip-bootstrap-platform-state` | `terraform/bootstrap/backend.tf` (backend blocks cannot use variables) |
| Region `us-east4`, BigQuery location `US` | Variable defaults in both layers |
| GitHub connection values | `terraform.tfvars`, after you create the connection |

`terraform.tfvars` is git-ignored. The org layer gets its IDs from a config file that the bootstrap layer writes to the state bucket, so no real IDs need to be committed.

## Getting started

Run the bootstrap steps as an organization administrator who can also manage the billing account.

1. **Configure.** Copy `terraform/bootstrap/terraform.tfvars.example` to `terraform.tfvars` and fill it in. Leave `quota_project` commented out for now.
2. **First apply, with local state.** The state bucket does not exist yet, so move `backend.tf` aside, then create the project and enable its APIs:
   ```bash
   cd terraform/bootstrap
   mv backend.tf backend.tf.off
   terraform init
   terraform apply -target=google_project_service.enabled
   ```
3. **Set the quota project.** Uncomment `quota_project` in `terraform.tfvars` and run `gcloud auth application-default set-quota-project <prefix>bootstrap`.
4. **Connect GitHub (console).** In the bootstrap project, open Cloud Build > Repositories > 2nd gen, create a GitHub host connection named `github` in your region, and install the Cloud Build GitHub App on this repository only. Copy the installation ID and the OAuth token secret version into `terraform.tfvars`:
   ```bash
   gcloud builds connections describe github --region=us-east4 --project=<prefix>bootstrap \
     --format="yaml(installationState,githubConfig)"
   ```
5. **Set up PAM (console), if needed.** If the full apply reports that the PAM service agent does not exist, open Privileged Access Manager for the bootstrap project and choose Set up PAM.
6. **Full apply.** Run `terraform apply`. It creates the buckets, identities, grants, PAM entitlements, CI records, and triggers, and imports the GitHub connection.
7. **Move state into the bucket.** Restore `backend.tf` with your bucket name, migrate, and confirm a clean plan:
   ```bash
   mv backend.tf.off backend.tf
   terraform init -migrate-state
   terraform plan
   ```
   Keep the local `terraform.tfstate` until the plan reports no changes, then move it offline.
8. **Seed the org state.** The read-only plan identity cannot create a state file, so create the empty org state once:
   ```bash
   terraform -chdir=../org init -backend-config=bucket=<prefix>bootstrap-platform-state -backend-config=prefix=org
   terraform -chdir=../org state list
   ```
9. **Protect `main` (GitHub).** Add a branch ruleset on the default branch: require a pull request, squash merges only, linear history, block force pushes and deletion, no bypass. Disable GitHub Actions for the repository.
10. **Remove standing access.** Remove the day-to-day administrator's organization roles and the project creator's Owner binding. From now on, bootstrap changes are applied by break-glass with a temporary Owner grant on the bootstrap project, removed straight after.

Then open a pull request that touches `terraform/org/`. Expected result: `pr-plan-org` shows the folder and policy plan, merging starts `main-plan-org` and a pending `apply-org`, and approving it as a member of `ai-governance` applies the plan and adds a row to the `ci_records.apply_records` table.

## Things to know

- New organizations already set several policies. The org layer imports them instead of recreating them; list yours with `gcloud org-policies list --organization=<ORG_ID>` and adjust the import list in `terraform/org/org-policies.tf` if it differs.
- Every new Terraform state needs the one-time seed from step 8 before its first CI plan.
- If an apply build times out, its lock object stays in the lock bucket. Confirm the build has ended, then delete `apply.lock` under a `state-recovery` grant or as break-glass.
- Every merge that touches a layer leaves an apply build waiting for approval, even when its plan has no changes. Reject those.
- Running cost is small: a few buckets, a BigQuery dataset, and Cloud Build minutes.
