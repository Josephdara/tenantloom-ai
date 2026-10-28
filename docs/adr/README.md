# Architecture Decision Records

These records explain why TenantLoom AI is designed the way it is. [architecture.md](../../architecture.md) describes the design itself; each record here captures the context, the options considered, the decision, and its consequences.

| ADR | Decision | Status |
|---|---|---|
| [ADR-001](ADR-001-environment-folders-with-tenant-projects.md) | Environment folders with tenant projects | Accepted |
| [ADR-002](ADR-002-layered-provisioning-and-state.md) | Layered provisioning identities, tenant state split, and plan-to-apply integrity | Accepted |
| [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md) | Catalog and entitlement enforcement | Accepted |
| [ADR-004](ADR-004-delivery-pipeline-and-gates.md) | Cloud Deploy, platform-owned mandatory gates, and approved staged rollout | Accepted |
| [ADR-005](ADR-005-deployment-patterns.md) | Deployment patterns | Accepted |
| [ADR-006](ADR-006-shared-prod-perimeter.md) | Shared prod perimeter with IAM isolation | Accepted |
| [ADR-007](ADR-007-model-armor-floor-settings.md) | Model Armor screening | Accepted |
| [ADR-008](ADR-008-regional-or-global-endpoint.md) | Regional or global model endpoint | Superseded by ADR-012 |
| [ADR-009](ADR-009-showback.md) | Showback from labels and billing export | Accepted |
| [ADR-010](ADR-010-api-invocation-boundaries.md) | Tenant API invocation boundaries and temporary production human access | Accepted |
| [ADR-011](ADR-011-tenant-local-evaluation.md) | Tenant-local evaluation jobs and dedicated environment identities | Accepted |
| [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md) | US jurisdiction model endpoint by default | Accepted |

## Status values

- **Proposed:** the decision is recorded, but it depends on open items listed in the record. Those items may change parts of it.
- **Accepted:** the decision is settled. Later changes require a new record that supersedes it.
- **Superseded:** replaced by a later record, which the superseded record links to.

Status describes the decision, not the implementation. Every record currently describes planned behavior that is not yet implemented or verified. Live checks that must pass before a control is relied on are listed in [Implementation verification](../../architecture.md#17-implementation-verification).

## Format

Each record contains a status table, context, decision drivers, options considered, the decision, consequences, implementation verification, and related records. Records follow a lightweight version of [MADR](https://adr.github.io/madr/).
