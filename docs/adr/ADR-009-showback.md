# ADR-009: Showback from labels and billing export

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-001](ADR-001-environment-folders-with-tenant-projects.md), [ADR-002](ADR-002-layered-provisioning-and-state.md), [ADR-005](ADR-005-deployment-patterns.md) |

## Context

Tenants and governance reviewers need to see what each tenant costs, by environment and by model. Every tenant environment is its own project carrying `tenant`, `env`, `cost-center`, and `data-class` labels, so most tenant cost is separable at the project level. Model-level cost within a project, and the cost of shared projects such as `jd-aip-bootstrap`, `jd-aip-ops`, `jd-aip-eval`, `jd-aip-kms`, and `jd-aip-prod-shared`, are not.

Budgets need a scope across the tenant's projects. Cloud Billing budgets can filter by projects, but project labels cannot be used as a budget scope. The starter template's daily token ceiling needs shared counting across replicas.

## Decision drivers

1. Cost attribution by tenant, environment, and model without new tooling.
2. Clear limits on what the numbers can and cannot show.
3. Budget alerts that reach the tenant and the platform team.
4. A token ceiling that holds across replicas without a standing service.
5. Reporting that informs tenants without operating an internal billing process.

## Options considered

### Reporting

| Option | Assessment |
|---|---|
| A. Billing export to BigQuery joined with project labels, plus token usage from application logs | Uses existing data; project-level cost is exact, model-level cost depends on SKU detail |
| B. A third-party FinOps tool | Richer analysis, but an external system and integration to maintain |
| C. Token-based estimates only | Simple per-model view, but misses non-model cost and drifts from billed cost |
| D. Chargeback with internal invoicing | Stronger cost accountability, but requires financial processes outside this platform |

### Budget scope

| Option | Assessment |
|---|---|
| A. One budget per tenant across its projects, owned by the org layer | Matches the tenant field; needs billing-account budget permission, which `sa-org` already holds for billing export |
| B. One budget per project, owned by the tenant states | Project-level permissions suffice, but the tenant amount must be split arbitrarily |
| C. A label-filtered budget | Project labels cannot be used as a budget scope, and only one label is allowed |

### Token counter

| Option | Assessment |
|---|---|
| A. Firestore counter per environment project, one document per UTC day, atomic increment | Shared across replicas, no standing instance, stays inside each project |
| B. Memorystore | Atomic and fast, but standing instance and network cost |
| C. Per-instance memory | Not shared; the limit multiplies with scale-out |
| D. Central counter in `jd-aip-ops` | Shared across environments, but adds a prod egress path and a store shared across tenants |

## Decision

Use option A for reporting (showback, not chargeback), option A for budget scope, and option A for the token counter.

- Billing export goes to BigQuery in `jd-aip-ops` and is joined with project labels set by the factory.
- `budget_monthly_usd` is one monthly budget per tenant, covering all of its projects through a project filter. The org layer owns it and creates it in onboarding step 4, after the projects exist. Alerts at 50%, 90%, and 100% of actual spend go to the tenant channel and the platform team. Budgets notify; they do not stop spending.
- The org layer also owns one budget across the shared projects and one across the billing account.
- Shared project costs are unallocated platform cost. Each tenant report shows the total for context, and tenant budgets exclude it. The platform report breaks it down by the `tenant` resource label wherever one exists.
- Model cost uses billed Agent Platform cost by SKU where the SKU identifies the model, with token-based estimates beside it. Token volume comes from a log-based metric, and monthly totals are copied to a showback dataset before the metric's 6-week retention ends.
- The daily token ceiling applies per environment. It uses a Firestore counter in each environment project that runs the tenant service, one document per UTC day, checked before and atomically incremented after each model call. If the store is unavailable, the service fails open with a log entry and an alert. Tenants own the ceiling value in their release configuration.
- Each tenant receives a monthly report with cost by environment and model, token volume, budget status, and the unallocated platform total, sent to its owners group.

## Consequences

**Positive**

- No new tooling, and cost is visible per tenant and environment.
- Labels come from the validated tenant schema, so attribution does not depend on manual tagging.
- The factory holds no budget permission, so it cannot change other tenants' budgets.

**Negative and accepted risks**

- Model-level cost depends on SKU detail in the billing export. Token-based estimates may not reconcile exactly.
- Shared project costs are visible but not allocated.
- Billing export data is not real time, so reports trail actual spend.
- `sa-org` holds a billing-account role that covers every budget.
- The token ceiling can be overshot by requests in flight, fails open, and is tenant-owned code. Budgets and instance caps are the platform-enforced bounds.

## Implementation verification

- A multi-project budget reports spend across all of a tenant's projects, and its notification channels work from their chosen project.
- Billing Account Costs Manager covers billing export and budgets for `sa-org`, and how billing export is configured.
- Model SKUs and shared-resource labels appear in the billing export.
- Firestore availability in `us-east4`, concurrent increments, free-quota fit, and behavior under the perimeter.
- Each catalog model's response reports a total token count.
- Launch stage and Terraform support for spend cap budgets, kept as a future option.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-001](ADR-001-environment-folders-with-tenant-projects.md): one project per tenant environment makes project-level attribution possible.
- [ADR-002](ADR-002-layered-provisioning-and-state.md): the org layer owns budgets, and the factory sets labels and token counters.
- [ADR-005](ADR-005-deployment-patterns.md): self-deployed endpoints carry dedicated hardware cost and are limited to `jd-aip-eval`.
