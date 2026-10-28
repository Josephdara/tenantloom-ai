# ADR-001: Environment folders with tenant projects

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-002](ADR-002-layered-provisioning-and-state.md), [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md), [ADR-006](ADR-006-shared-prod-perimeter.md) |

## Context

TenantLoom AI gives every tenant sandbox, dev, test, and prod environments, and controls tighten toward prod: prod requires an enforced service perimeter, Binary Authorization, CMEK, and no standing human roles, while sandbox allows console experimentation. Google Cloud folders carry organization policies and IAM down to the projects beneath them, so the folder structure decides where each control can be attached once and inherited.

The hierarchy has to support two groupings at the same time: by environment, because that is how controls differ, and by tenant, because that is how ownership, isolation, and cost reporting work. A folder tree can only make one of these the primary axis.

## Decision drivers

1. Controls that differ by environment attach once and are inherited by every new tenant without per-tenant setup.
2. Tenant isolation is enforced at the project boundary.
3. The number of folder-level objects to manage stays small.
4. Tenant ownership and cost remain visible without a tenant folder.

## Options considered

| Option | Advantages | Disadvantages |
|---|---|---|
| A. Environment folders (`platform`, `nonprod`, `prod`) containing tenant projects | Prod controls attach once to the prod folder; a new tenant inherits them on creation | Tenant-wide settings cannot be set on a folder; tenant identity comes from labels, groups, and service accounts |
| B. Tenant folders containing environment projects | Tenant IAM and reporting attach to one folder | Every prod control must be repeated in each tenant folder, so each onboarding adds places where prod controls can drift |
| C. Environment folders with a tenant subfolder in each | Both groupings exist as folders | Folder count grows with tenants times environments for little benefit at the planned scale |
| D. One project per tenant, with environments separated inside it | Fewest projects | No project boundary between prod and nonprod; prod-only controls cannot be applied |

Option B becomes reasonable if tenants need substantially different guardrails from one another. Option C becomes reasonable if tenant-level folder IAM is required later, at the cost of more folders.

## Decision

Use option A. The `ai-platform` folder contains `platform`, `nonprod`, and `prod` folders. Tenant sandbox, dev, and test projects go in `nonprod`, and tenant prod projects go in `prod`. Shared platform projects (`jd-aip-bootstrap`, `jd-aip-ops`, `jd-aip-eval`, `jd-aip-kms`, `jd-aip-prod-shared`) go in `platform`.

- Organization policies and folder-level settings carry the common baseline. The `ai-platform` folder denies all models by default, and each project that needs models receives its own generated policy ([ADR-003](ADR-003-catalog-and-entitlement-enforcement.md)).
- Data Access audit logging and the aggregated log sink attach to the `ai-platform` folder, so new projects are covered from creation.
- Tenants are identified by `tenant`, `env`, `cost-center`, and `data-class` project labels, by tenant groups, and by per-tenant service accounts.
- Tenant-specific controls, such as IAM bindings and model policies, are set per project by the provisioning layers ([ADR-002](ADR-002-layered-provisioning-and-state.md)).
- Perimeter membership is not inherited from folders; it is generated explicitly ([ADR-006](ADR-006-shared-prod-perimeter.md)).

## Consequences

**Positive**

- Prod-wide controls exist in one place, and a new tenant's prod project inherits them immediately.
- Onboarding a tenant adds projects, not folders.
- Because each tenant environment is its own project, project-level grants are scoped to one tenant and one environment, which the invocation and evaluation designs rely on.

**Negative and accepted risks**

- The `nonprod` folder holds environments with different controls. Sandbox, dev, and test differences, such as the Model Armor mode and dry-run perimeter membership for test, are set per project rather than inherited.
- There is no folder-level tenant boundary. Isolation depends on project IAM, per-tenant identities, and per-tenant keys, which access reviews and persona tests must verify.
- Tenant views in reporting depend on accurate labels, so labels are set by the provisioning layers and validated from the tenant schema rather than edited by hand.

## Implementation verification

- A project created under the `ai-platform` folder has no model access until its generated policy is applied.
- Persona tests confirm that no tenant group can reach another tenant's projects.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-002](ADR-002-layered-provisioning-and-state.md): the tenant state layout follows these environment folders.
- [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md): the model access default attaches to the `ai-platform` folder.
- [ADR-006](ADR-006-shared-prod-perimeter.md): the prod perimeter covers the projects in the `prod` folder and `jd-aip-prod-shared`.
