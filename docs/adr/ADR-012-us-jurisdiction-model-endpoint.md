# ADR-012: US jurisdiction model endpoint by default

| Field | Value |
|---|---|
| Status | Accepted |
| Supersedes | [ADR-008](ADR-008-regional-or-global-endpoint.md) |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md), [ADR-005](ADR-005-deployment-patterns.md), [ADR-007](ADR-007-model-armor-floor-settings.md) |

## Context

The platform's residency intent is US locations, with `us-east4` as the primary region. The `gcp.resourceLocations` organization policy restricts where resources are created, but it does not determine where a model request is processed.

Agent Platform (Vertex AI) offers regional endpoints, `us` and `eu` multi-region endpoints, and a global endpoint. A regional endpoint in the US processes within the US. The `us` multi-region endpoint keeps ML processing within the US. The global endpoint gives no processing-location guarantee. Current GA Gemini models are offered on the global and multi-region endpoints, not on `us-east4`.

## Decision drivers

1. Requests processed within the US by default.
2. Access to current GA Gemini models.
3. Residency trade-offs recorded and approved explicitly.
4. A single rule that every tenant follows.

## Options considered

| Option | Assessment |
|---|---|
| A. Regional endpoints only; other models are not allowed | No current GA Gemini model is offered regionally in the US, so the catalog would have no Gemini models |
| B. Global endpoint by default | Best availability, but no guarantee of processing location for any tenant |
| C. Regional endpoint by default; global only through a recorded exception | Superseded approach; leaves current Gemini models needing exceptions |
| D. Regional endpoint where offered, otherwise the `us` multi-region; global only by exception | US processing for current GA Gemini models, with deliberate exceptions |

## Decision

Use option D.

- Workloads call the `us-east4` regional endpoint when the model offers it, otherwise the `us` multi-region endpoint.
- Each catalog entry records its endpoint.
- A catalog model available only on the global endpoint requires its own decision record, stating the residency trade-off, the permitted classifications, and `ai-governance` approval.
- Candidate evaluation in `jd-aip-eval` with synthetic or public data may use the global endpoint without its own record; the candidate entry records the endpoint.
- No organization policy enforces the endpoint. CI checks each release's model configuration against the catalog, and an audit query flags calls to other endpoints.
- A resource-location policy is not treated as proof of model processing location.

## Consequences

**Positive**

- Model requests for current GA Gemini models are processed within the US.
- Every residency exception is visible and approved.

**Negative and accepted risks**

- Model Armor floor settings do not apply on the multi-region endpoint, so the starter template sanitizes prompts and responses on every permitted endpoint, including regional endpoints and any global exception ([ADR-007](ADR-007-model-armor-floor-settings.md)).
- Private Google Access does not support multi-region endpoints. Test and prod workloads have no internet egress ([ADR-006](ADR-006-shared-prod-perimeter.md)), so they reach the `us` endpoint through a Private Service Connect endpoint in each project.
- Regional and multi-region capacity may differ from global capacity, which affects 429 handling.
- Endpoint compliance depends on CI checks and audit queries, not an organization policy.

## Implementation verification

- Recheck each model's endpoints and lifecycle group when its catalog entry is created.
- Calls to the `us` multi-region endpoint work under the prod perimeter.
- Data Access audit entries record the request location, so the audit query can flag calls whose endpoint differs from the catalog entry.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md): catalog entries record the endpoint and permitted classifications.
- [ADR-005](ADR-005-deployment-patterns.md): pattern availability varies by location.
- [ADR-007](ADR-007-model-armor-floor-settings.md): screening on every permitted endpoint.
- [ADR-008](ADR-008-regional-or-global-endpoint.md): the superseded regional-first rule.
