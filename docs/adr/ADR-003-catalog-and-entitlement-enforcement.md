# ADR-003: Catalog and entitlement enforcement

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-001](ADR-001-environment-folders-with-tenant-projects.md), [ADR-002](ADR-002-layered-provisioning-and-state.md), [ADR-005](ADR-005-deployment-patterns.md), [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md) |

## Context

Tenants should use only models the organization has evaluated and approved, only for data classifications those models are approved for, and only in the environments their entitlements name. A tenant must not be able to widen its own access, and an unapproved model call should fail regardless of what the tenant's code does.

Two decisions are involved and kept separate: **catalog admission** (whether a model is approved for the organization) and **tenant entitlement** (whether a specific tenant may use an approved model in a specific environment). Models still under evaluation also need somewhere to run without reaching tenants.

The `vertexai.allowedModels` constraint takes values of the form `publishers/PUBLISHER/models/MODEL_ID:ACTION`, with actions `predict`, `deploy`, and `tune`. When no policy is set or inherited, all models are allowed. It covers Model Garden models, not models in Model Registry or calls to an already deployed endpoint.

## Decision drivers

1. Enforcement by the platform, not by tenant application code.
2. Fail closed: no project has model access until it receives its own policy.
3. Every change to model access goes through review.
4. Entitlements are granular per tenant and per environment.
5. Unreviewed models never reach tenant projects.

## Options considered

### Enforcement mechanism

| Option | Assessment |
|---|---|
| A. Application-level checks in the starter template | Easy to build, but tenant code controls it and can bypass it |
| B. IAM only, through the custom Gemini Invoker role | Controls who can call prediction, but not which model |
| C. Per-project `vertexai.allowedModels` organization policy generated from entitlements, plus catalog checks in CI | Enforced by the platform for every caller in the project; requires a policy per project |
| D. A central model gateway that every call passes through | Strong control and observability, but a new service to build and operate, and a latency and availability dependency for every tenant |

Option D becomes reasonable if the platform later needs per-request policy, quotas, screening, or logging that organization policy cannot express.

### Who sets the policy

The org layer (`sa-org`) generates the policies, rather than the tenant factory, so the identity that runs for every tenant holds no organization policy authority ([ADR-002](ADR-002-layered-provisioning-and-state.md)).

### Default for projects without their own policy

| Option | Assessment |
|---|---|
| A. No default | Every project without a policy can use every model, including platform projects |
| B. Deny all on the `nonprod` and `prod` folders | Tenant projects fail closed, but platform projects still allow every model |
| C. Deny all on the `ai-platform` folder, replaced per project by a generated policy | Every project fails closed until it receives its own policy |

### Candidate models

| Option | Assessment |
|---|---|
| A. A sandbox-only candidate state in the catalog | Gives tenants models no governance review has approved; synthetic-data-only is a rule, not a control; no speed benefit, because sandbox entitlements still need an org apply |
| B. Candidates listed separately and evaluated only by the platform team in `jd-aip-eval` | The catalog stays the single list of approved models; preview and global-only models stay out of tenant projects |

## Decision

Use option C for enforcement, the org layer for policy generation, option C for the default, and option B for candidates.

- `catalog/catalog.yaml` lists approved models only, each with publisher, exact model ID (the pin), launch stage (GA required), deployment pattern, endpoint, permitted data classifications, eval report, approver and approval record, retirement information when announced, and next review. The catalog prefers models with Google's longer availability commitment; a short-term model needs governance approval that records its shorter notice.
- `catalog/candidates.yaml` lists models under platform evaluation, with model ID, pattern, endpoint, launch stage, purpose, requester, and evaluation expiry. Candidates are never entitled to tenants.
- Tenants request entitlements in their tenant file. CI rejects models that are not in the catalog, including candidates; models not approved for the tenant's classification; expired candidates; catalog entries that are not GA; and global-endpoint entries without an exception record.
- The org layer generates a `vertexai.allowedModels` policy for each tenant project with `inheritFromParent: false`. Tenant projects receive `predict` only, in every environment.
- The org layer generates the `jd-aip-eval` policy from catalog entries and candidates, adding `deploy` for self-deployed models. No project receives `tune`.
- The `ai-platform` folder denies all models, so new projects and platform projects without their own policy have no model access.
- Only `sa-org` holds Organization Policy Administrator.
- Catalog additions: request, candidate entry, evaluation in `jd-aip-eval`, pull request moving the entry to the catalog with the eval report, `ai-governance` approval. Rejected or expired candidates are removed.
- The security gate includes a call to a non-entitled model, which must be denied.

## Consequences

**Positive**

- Model access fails closed everywhere and does not depend on tenant code.
- Neither tenants nor the tenant factory can widen model access.
- Entitlement changes are reviewed pull requests with an audit trail.

**Negative and accepted risks**

- Every entitlement change, including a sandbox-only change, requires an org-layer apply with prod-level approval.
- The constraint does not cover Model Registry models or calls to an already deployed endpoint, so self-deployed serving relies on zero GPU serving quota in tenant projects and on IAM.
- The constraint does not govern endpoint location. CI and an audit query cover that instead ([ADR-012](ADR-012-us-jurisdiction-model-endpoint.md)).
- Tenants cannot try uncataloged models themselves; candidate evaluation depends on the platform team.

## Implementation verification

- Entitled calls succeed and non-entitled calls are denied on both the `us` and global endpoints.
- The methods the starter template uses, such as token counting, are covered by `predict`.
- A project with no generated policy under the `ai-platform` deny-all default is denied.
- A candidate model call succeeds in `jd-aip-eval` while the same model is denied in a tenant sandbox.
- The exact `deploy` value for the chosen Gemma and the `predict` value for the Gemma managed API are recorded.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-001](ADR-001-environment-folders-with-tenant-projects.md): the default deny attaches to the `ai-platform` folder.
- [ADR-002](ADR-002-layered-provisioning-and-state.md): the org layer and its identity.
- [ADR-005](ADR-005-deployment-patterns.md): catalog entries record a deployment pattern.
- [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md): catalog entries record the endpoint and any residency exception.
