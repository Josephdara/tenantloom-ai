# TenantLoom AI

TenantLoom AI is a small governed AI platform I am building on Google Cloud. It gives teams in an organization access to Gemini and Model Garden models without giving up isolation, cost visibility, or change control. A platform team owns the guardrails: the model catalog, organization policies, the prod service perimeter, and the delivery gates. A team onboards by opening a pull request with a short request file, and a Terraform tenant module turns it into a ready-to-use slice of the platform: groups, service accounts, a delivery pipeline, a dataset bucket, a budget, and a dashboard.

I use it to show how an organization can offer models to several teams in a few shared projects, with every release evaluated, attested, and rolled out as a canary before it serves prod traffic. The full design is in [architecture.md](architecture.md).

## Status

Everything is planned. No part of the design is implemented or verified yet.

| Area | State |
|---|---|
| Foundation: folder, three projects, state bucket, `sa-terraform`, platform plan and apply trigger | Planned |
| Governance and access: model catalog allowlists, organization policies, identity matrix, PAM, audit sink, Model Armor, perimeter in dry run | Planned |
| Evaluation: versioned datasets, harness, evaluation records, catalog comparison | Planned |
| Tenant module and delivery: starter template, Cloud Deploy pipeline, gates, attestation, canary, rollback | Planned |
| Second team, operations, and documentation | Planned |

Platform behavior I still need to confirm in the lab is listed under [Lab checks](architecture.md#15-lab-checks), and the reasoning behind the foundation and delivery design is in [docs/adr](docs/adr/).

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
- All Terraform runs in Cloud Build. Pull requests plan with a read-only identity, and merged changes apply as `sa-terraform` after approval. After a one-time bootstrap, no person applies Terraform directly.

## Planned repository layout

```text
terraform/                  platform root: bootstrap set, org policies, projects, perimeter, platform IAM
terraform/modules/tenant/   team slice
tenants/                    one request file per team
catalog/                    approved models and eval reports
verification/               platform-owned gate jobs and minimum thresholds
templates/starter-service/  starter Cloud Run service for new teams
eval/                       harness and evaluation record schema
cloudbuild/                 platform plan and apply, tenant build template
docs/                       guides, runbooks, ADRs, diagrams, evidence
architecture.md             target architecture
```

## Prerequisites

- A Google Cloud organization (Cloud Identity Free is enough) and a billing account that can link at least three more projects.
- An administrator account that can create folders and projects and grant organization and billing roles, for the one-time bootstrap.
- Groups for platform administrators, `ai-governance` approvers, and `auditors`. Keep approvers separate from the people who request changes.
- A GitHub repository holding this code, connected to Cloud Build.
- Terraform and the Google Cloud CLI.

## Values you must replace

| Value | Planned value |
|---|---|
| Organization domain | `josephdara.com` |
| Folder | `ai-platform` |
| Project IDs | `jd-aip-sandbox`, `jd-aip-nonprod`, `jd-aip-prod` |
| Region | `us-east4` |
| Group and alert addresses | `ai-governance@`, `auditors@`, and each team's owners and alert addresses |
| Team request files | `tenants/docs.yaml` and `tenants/support.yaml` |
| Prod load balancer DNS name | A hostname under your domain, for the Google-managed certificate |

Where each value is set will be documented here once the bootstrap and Terraform code exist.

## Getting started

There is nothing to run yet. Start with [architecture.md](architecture.md) to see the design, the identity matrix, and the gates every release must pass. Bootstrap steps, onboarding instructions, and expected results will be added as each component is built and verified.

When the build is complete, the expected result is two teams, `docs` and `support`, each serving in prod after releasing and rolling back through its own pipeline, with onboarding and offboarding run from pull requests.
