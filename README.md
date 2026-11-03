# TenantLoom AI

TenantLoom AI is a small governed AI platform I am building on Google Cloud. It gives teams in an organization access to Gemini and Model Garden models without giving up isolation, cost visibility, or change control. A platform team owns the guardrails: the model catalog, organization policies, the prod service perimeter, and the delivery gates. A team onboards by opening a pull request with a short request file, and a Terraform tenant module turns it into a ready-to-use slice of the platform: access for the team's groups, service accounts, a delivery pipeline, a dataset bucket, a budget, and a dashboard.

I use it to show how an organization can offer models to several teams in a few shared projects, with every release evaluated, attested, and rolled out as a canary before it serves prod traffic. The full design is in [architecture.md](architecture.md).

## Status

| Area | State |
|---|---|
| Foundation: three projects, state bucket, CI identities, GitHub connection, plan and apply triggers, platform budget | Implemented and partly verified. Results and open items are in [foundation evidence](docs/evidence/foundation.md). |
| Governance and access: model catalog allowlists, organization policies, identity matrix, PAM, audit sink, Model Armor, prod network, perimeter in dry run | Implemented; verification in progress. Results are in [governance evidence](docs/evidence/governance.md). |
| Evaluation: versioned datasets, harness, evaluation records, catalog comparison | Planned |
| Tenant module and delivery: starter template, Cloud Deploy pipeline, gates, attestation, canary, rollback | Planned |
| Second team, operations, and documentation | Planned |

Platform behavior I still need to confirm in the lab is listed under [Lab checks](architecture.md#15-lab-checks), and the reasoning behind the design is in [docs/adr](docs/adr/).

## How it fits together

```text
jd-aip-sandbox   shared exploration and model evaluation, synthetic data only
jd-aip-nonprod   dev and test workloads, Terraform state, Cloud Build, Cloud Deploy,
                 Artifact Registry, golden datasets, audit and eval data
jd-aip-prod      prod workloads behind a service perimeter and load balancer, CMEK keys
```

- Teams share projects and are kept apart by service accounts, Cloud Run services, buckets, and IAM.
- Each project's `vertexai.allowedModels` policy is generated from `catalog/catalog.yaml`. CI rejects a release that names a model the team is not entitled to.
- A release moves from dev to test automatically. It reaches prod only after the eval, latency, and security gates pass, a passed-test attestation is signed, and a team release approver approves. Prod rolls out at 10%, 50%, then 100%, and rolls back automatically if canary verification fails.
- Prod traffic enters through an external Application Load Balancer, and prod services send all outbound traffic through a VPC that reaches only Google APIs inside the perimeter. The load balancer has a fixed monthly charge even when idle.
- All Terraform runs in Cloud Build. Pull requests plan with a read-only identity. On merge, an approver releases the plan and then approves the saved plan before it is applied. After a one-time bootstrap, no person applies Terraform directly.

## Repository layout

```text
terraform/                  platform root and its modules (projects, state, CI identities, Cloud Build, billing,
                            governance, audit, perimeter)
catalog/                    approved models; Terraform generates each project's model allowlist from it
cloudbuild/                 pull request plan, merge plan, and apply build configs
.github/CODEOWNERS          code owner for every path
docs/adr/                   architecture decision records
docs/runbooks/              operating procedures, starting with bootstrap
docs/evidence/              verification results
architecture.md             target architecture
```

Planned later: `terraform/modules/tenant/`, `tenants/`, `verification/`, `templates/starter-service/`, and `eval/`.

## Prerequisites

- A Google Cloud organization (Cloud Identity Free is enough) and a billing account that can link three more projects.
- A break-glass administrator account with Organization Administrator and Billing Account Administrator. Expect it to re-authenticate often if your organization enforces session limits.
- Cloud Identity groups created by an administrator in the Admin console. Terraform manages no groups.
  - `ai-governance`, holding at least one approver account that is not the account that writes pull requests.
  - `auditors` and `ai-platform-admins`, before the governance work.
  - For each team, `<id>-developers` and `<id>-release-approvers`, before the team's onboarding pull request.
- A GitHub repository holding this code, with the Google Cloud Build GitHub App installed on it and a branch ruleset on `main`.
- Terraform 1.16.4, the Google Cloud CLI, and the GitHub CLI.

## Values you must replace

| Value | Planned value | Where it is set |
|---|---|---|
| Organization ID, billing account, and `ai-platform` folder ID | Your own | Local values file during bootstrap, then the CI configuration object in the state bucket |
| Project ID prefix | `jd-aip-` | Same, as `project_prefix` |
| Region | `us-east4` | Same, as `region` |
| Approver group | `ai-governance@` your domain | Same, as `governance_group` |
| Platform administrator group | `ai-platform-admins@` your domain | Same, as `platform_admins_group` |
| Auditor group | `auditors@` your domain | Same, as `auditors_group` |
| Access policy | Your organization's existing access policy ID | Same, as `access_policy_id` |
| Break-glass account | Your break-glass administrator | Same, as `breakglass_account` |
| Budget alert address | Your own | Same, as `budget_alert_email` |
| Monthly platform budget | 100 in the billing account's currency | `budget_amount` in `terraform/variables.tf` |
| GitHub repository URI and code owner | Your own | `platform_repo_uri`, and `.github/CODEOWNERS` |
| Prod load balancer DNS name | A hostname under your domain | Same, as `prod_hostname` |
| Approved models | `gemini-3.8-flash`, with `gemini-4-argon` as a sandbox candidate | `catalog/catalog.yaml` |

Values that identify your organization or people stay out of the repository. CI reads them from the configuration object at build time.

## Getting started

Follow the [bootstrap runbook](docs/runbooks/bootstrap.md). It walks through the two local bootstrap passes, the GitHub connection, moving state into the bucket, and handing control to CI. When it is done, every change goes through a pull request:

1. Open a pull request. The `platform-pr-plan` check shows the plan.
2. Merge it. As an `ai-governance` member, approve the `platform-merge-plan` build in Cloud Build.
3. Read the saved plan through the `cloudbuild` log view, then approve the `platform-apply` build.

When the build is complete, the expected result is two teams, `docs` and `support`, each serving in prod after releasing and rolling back through its own pipeline, with onboarding and offboarding run from pull requests.
