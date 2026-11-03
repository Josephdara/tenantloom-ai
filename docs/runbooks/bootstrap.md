# Bootstrap runbook

This runbook creates the TenantLoom AI foundation from an empty folder and hands it to CI. After it, every change goes through a pull request, two Cloud Build approvals, and `sa-terraform`. It also covers the break-glass tasks that remain afterward: adding a private CI input, recovering state, and releasing a stuck lock.

Run every command in **one terminal tab**. The access token in `GOOGLE_OAUTH_ACCESS_TOKEN` exists only in the tab that set it.

## Values to replace

Every value below is specific to one deployment. Replace it before running anything.

| Placeholder | Meaning | Example |
|---|---|---|
| `ORG_ID` | Numeric organization ID | `123456789012` |
| `BILLING_ACCOUNT` | Billing account ID | `XXXXXX-XXXXXX-XXXXXX` |
| `FOLDER_ID` | Numeric ID of the existing `ai-platform` folder | `987654321098` |
| `BREAKGLASS` | Break-glass administrator account | `breakglass@example.com` |
| `GOVERNANCE_GROUP` | Approver group | `ai-governance@example.com` |
| `ALERT_EMAIL` | Budget alert address | `alerts@example.com` |
| `PREFIX` | Project ID prefix | `jd-aip-` |
| `REGION` | Region | `us-east4` |
| `OWNER/REPO` | GitHub repository | `example/tenantloom-ai` |

The nonprod project is `${PREFIX}nonprod`, and the state bucket is `${PREFIX}nonprod-tfstate`.

## Before you start

- **Groups.** Create `GOVERNANCE_GROUP` in the Admin console and add an approver account that is not the account that writes pull requests. Terraform manages no groups.
- **Break-glass roles.** `BREAKGLASS` holds Organization Administrator and Billing Account Administrator.
- **Repository.** This repository is on GitHub, and you are its administrator. `.github/CODEOWNERS` names your GitHub user.
- **Tools.** Terraform 1.16.4, the Google Cloud CLI, and the GitHub CLI.
- **Project IDs.** The three project IDs are globally unique, and the billing account has three free project links.

## 1. Sign in

Organizations with session limits force break-glass accounts to re-authenticate often. Start each break-glass task here.

```bash
export CLOUDSDK_BILLING_QUOTA_PROJECT=LEGACY
gcloud auth login BREAKGLASS --force
gcloud config set account BREAKGLASS
gcloud config unset project
```

**Expected:** a browser sign-in, then `You are now logged in as [BREAKGLASS]`.

## 2. Grant temporary project creation

```bash
gcloud resource-manager folders add-iam-policy-binding FOLDER_ID \
  --member="user:BREAKGLASS" --role="roles/resourcemanager.projectCreator" \
  --condition=None --quiet --format="value(etag)"
```

**Expected:** one etag line. Step 9 removes this role.

## 3. Prepare local state and inputs

The repository's `terraform/backend.tf` points at the state bucket, which does not exist yet. A local override file keeps state on the workstation until step 7. Never commit it or the values file.

```bash
printf 'terraform {\n  backend "local" {}\n}\n' > terraform/backend_override.tf
cat > terraform/platform.auto.tfvars.json <<'EOF'
{
  "org_id": "ORG_ID",
  "billing_account": "BILLING_ACCOUNT",
  "folder_id": "FOLDER_ID",
  "region": "REGION",
  "project_prefix": "PREFIX",
  "governance_group": "GOVERNANCE_GROUP",
  "budget_alert_email": "ALERT_EMAIL",
  "platform_repo_uri": "https://github.com/OWNER/REPO.git",
  "github_connection_name": "github",
  "github_connection_authorized": false,
  "github_app_installation_id": null,
  "github_oauth_token_secret_version": null
}
EOF
git check-ignore -v terraform/platform.auto.tfvars.json
```

**Expected:** `git check-ignore` prints the `*.tfvars.json` rule. If it prints nothing, stop: the file would be committed.

## 4. Pass 1: projects, state bucket, CI identities

```bash
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --account=BREAKGLASS)
terraform -chdir=terraform init -input=false
terraform -chdir=terraform plan -input=false -out=pass1.tfplan
```

**Expected:** one import (the folder) and only creates, with nothing changed or destroyed. Review the plan, then apply it:

```bash
terraform -chdir=terraform apply -input=false pass1.tfplan
```

**Recovery:** if the apply stops partway, for example on a billing link limit, local state keeps what was created. Fix the cause, then plan and apply again. Some APIs, such as Billing Budgets, refuse user credentials without a quota project; if only those resources fail, continue, because pass 2 sets the quota project and creates them.

## 5. Create and authorize the GitHub connection

Terraform cannot create the connection, because the Cloud Build API rejects one without GitHub settings. Create it with gcloud, then authorize it.

```bash
gcloud builds connections create github github --region=REGION --project=${PREFIX}nonprod
gcloud builds connections describe github --region=REGION --project=${PREFIX}nonprod \
  --format="value(installationState.stage,installationState.actionUri)"
```

1. Open the printed link as `BREAKGLASS`.
2. Sign in to GitHub as the repository owner and authorize Google Cloud Build.
3. Install the Google Cloud Build app on **only** this repository.

Then read the values pass 2 needs:

```bash
gcloud builds connections describe github --region=REGION --project=${PREFIX}nonprod \
  --format="value(installationState.stage,githubConfig.appInstallationId,githubConfig.authorizerCredential.oauthTokenSecretVersion)"
```

**Expected:** `COMPLETE`, an installation ID, and a secret version path.

## 6. Pass 2: import the connection, add the triggers

In `terraform/platform.auto.tfvars.json`, set `github_connection_authorized` to `true`, set the installation ID and the secret version path exactly as printed, and add `"quota_project": "PREFIXnonprod"` (your nonprod project ID).

```bash
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --account=BREAKGLASS)
terraform -chdir=terraform plan -input=false -out=pass2.tfplan
```

**Expected:** the connection imported with no changes; the repository link and three triggers added; the CI configuration object updated. Apply it:

```bash
terraform -chdir=terraform apply -input=false pass2.tfplan
```

## 7. Move state into the bucket

Do this before opening any pull request. A pull request plan against an empty bucket would propose recreating everything.

```bash
rm terraform/backend_override.tf
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --account=BREAKGLASS)
terraform -chdir=terraform init -migrate-state \
  -backend-config=bucket=${PREFIX}nonprod-tfstate -backend-config=prefix=platform
terraform -chdir=terraform plan -input=false
```

Answer `yes` to copy the state. **Expected:** `Successfully configured the backend "gcs"!`, then `No changes.`

## 8. Hand control to CI

1. Open a pull request. The `platform-pr-plan` check runs as `sa-terraform-plan` and should report no changes.
2. Merge it. In Cloud Build, as an approver from `GOVERNANCE_GROUP`, approve the `platform-merge-plan` build.
3. That build saves the plan and starts `platform-apply`. Read the saved plan through the `cloudbuild` log view, then approve the apply.

**Expected:** both builds succeed with no changes. Approvals must come from an approver account. Until step 9, the break-glass account can also approve, because it is still project Owner.

## 9. Remove bootstrap access

Google makes the project creator Owner of each project. Remove it, the temporary role, and every local copy of state.

```bash
for p in ${PREFIX}sandbox ${PREFIX}nonprod ${PREFIX}prod; do
  gcloud projects remove-iam-policy-binding "$p" --member="user:BREAKGLASS" \
    --role="roles/owner" --condition=None --quiet --format="value(etag)" && echo "removed owner on $p"
done
gcloud resource-manager folders remove-iam-policy-binding FOLDER_ID \
  --member="user:BREAKGLASS" --role="roles/resourcemanager.projectCreator" \
  --condition=None --quiet --format="value(etag)"
rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup terraform/*.tfplan
```

**Expected:** three `removed owner` lines and one etag. Afterwards `BREAKGLASS` can no longer read the state bucket or plan locally, which is intended.

## 10. Protect `main`

Create or update a branch ruleset on `main`. The bypass lets a single maintainer merge their own pull requests through `gh pr merge --admin`, and GitHub records each bypass. Remove the bypass actor if a second reviewer joins.

```bash
gh api -X POST repos/OWNER/REPO/rulesets --input - <<'EOF'
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [{ "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" }],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "pull_request", "parameters": {
        "allowed_merge_methods": ["merge", "squash", "rebase"],
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": true,
        "required_approving_review_count": 1,
        "required_review_thread_resolution": true } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [{ "context": "platform-pr-plan (PREFIXnonprod)", "integration_id": 10529 }] } }
  ]
}
EOF
```

Use your nonprod project ID in the check name. `10529` is the Google Cloud Build GitHub App. **Expected:** `gh pr merge` without `--admin` on an unapproved pull request fails with "the base branch policy prohibits the merge."

## Steps outside Terraform

| Step | Where |
|---|---|
| Cloud Identity groups and their membership | Admin console |
| GitHub connection creation, authorization, and app installation | gcloud and browser, step 5 |
| Removing the creator's Owner role and the temporary role | gcloud, step 9 |
| Branch ruleset | GitHub API, step 10 |
| Private CI inputs | Configuration object in the state bucket, below |
| Cloud Billing export to BigQuery | Billing console, below. Not yet enabled in this deployment. |
| Organization custom role `terraformLogConfigReader` (`logging.sinks.get`, `logging.sinks.list`) | gcloud, with a temporary Organization Role Administrator grant |
| Organization log sink `identity-audit` to the nonprod `identity-audit` bucket, and Log Bucket Writer for its writer identity in nonprod | gcloud, with a temporary Logs Configuration Writer grant |
| Sharing Cloud Identity data with Google Cloud | Admin console: Account settings, Legal and compliance, Sharing options |
| Organization-level Privileged Access Manager service agent | `gcloud beta services identity create --service=privilegedaccessmanager.googleapis.com --organization=ORG_ID`, with a temporary Service Usage Admin grant |
| Delegating the prod hostname to the Cloud DNS zone | Your registrar: NS records for the hostname, using the zone's name servers from the `prod_name_servers` output |

## Add a private CI input

CI loads its inputs from `config/platform.auto.tfvars.json` in the state bucket, and Terraform rewrites that object from the same inputs. A change that adds a new required input therefore needs the key written once, before its pull request.

```bash
gcloud projects add-iam-policy-binding ${PREFIX}nonprod --member="user:BREAKGLASS" \
  --role="roles/storage.objectAdmin" --condition=None --quiet --format="value(etag)"
gcloud storage cat gs://${PREFIX}nonprod-tfstate/config/platform.auto.tfvars.json > /tmp/ci-config.json
python3 -I -c '
import json
p = "/tmp/ci-config.json"
d = json.load(open(p))
d["NEW_KEY"] = "NEW_VALUE"
open(p, "w").write(json.dumps(d, separators=(",", ":"), sort_keys=True))'
gcloud storage cp /tmp/ci-config.json gs://${PREFIX}nonprod-tfstate/config/platform.auto.tfvars.json --content-type=application/json
rm /tmp/ci-config.json
gcloud projects remove-iam-policy-binding ${PREFIX}nonprod --member="user:BREAKGLASS" \
  --role="roles/storage.objectAdmin" --condition=None --quiet --format="value(etag)"
```

The compact, key-sorted format matches what Terraform writes. The next merge rewrites the object with identical content.

## Recover a damaged state

Use this only if the state itself is damaged. Fix a failed apply forward through a pull request instead.

1. Confirm no `platform-apply` build is running.
2. Grant `roles/storage.objectAdmin` on the nonprod project to `BREAKGLASS`, as above.
3. List the state's versions and copy a known good one over the current object:

   ```bash
   gcloud storage ls -a -l gs://${PREFIX}nonprod-tfstate/platform/default.tfstate
   gcloud storage cp "gs://${PREFIX}nonprod-tfstate/platform/default.tfstate#GENERATION" \
     gs://${PREFIX}nonprod-tfstate/platform/default.tfstate
   ```

4. Remove the role, then open a pull request and confirm its plan matches what exists.

Noncurrent versions are kept for 30 days, and deleted objects stay recoverable through soft delete for 7 days.

## Release a stuck lock

Only after confirming that no plan or apply build is running in Cloud Build. With `roles/storage.objectAdmin` granted as above:

```bash
gcloud storage rm gs://${PREFIX}nonprod-tfstate/platform/default.tflock
```

Remove the role afterwards.

## Enable the Cloud Billing export

Showback reads the billing export in the `billing_export` dataset that platform Terraform creates in nonprod. A `US` dataset backfills the current and previous month only.

1. Grant `roles/bigquery.user` on the nonprod project to `BREAKGLASS`.
2. In **Billing > Billing export > BigQuery export**, edit **Standard usage cost** and **Detailed usage cost**, choosing the nonprod project and `billing_export`.
3. Remove the role.

Google adds its export service account to the dataset as owner. If the organization's domain restriction policy rejects that, the save fails with a policy error and needs a narrow policy exception for the nonprod project.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Reauthentication failed. cannot prompt during non-interactive execution` | The break-glass session expired | `gcloud auth login BREAKGLASS --force`, then set `GOOGLE_OAUTH_ACCESS_TOKEN` again |
| `invalid_rapt` from Terraform | No token set in this tab, so Terraform used expired saved credentials | Set `GOOGLE_OAUTH_ACCESS_TOKEN` in the same tab |
| `ACCESS_TOKEN_TYPE_UNSUPPORTED` | The token came from an expired session | Sign in again with `--force`, then set a new token |
| `Error 400` creating the budget | The budget currency differs from the billing account's | Leave the currency unset so the budget uses the account's |
| `Error 400: one of github_config ... must be specified` | Terraform tried to create the connection | Create it with gcloud, as in step 5 |
