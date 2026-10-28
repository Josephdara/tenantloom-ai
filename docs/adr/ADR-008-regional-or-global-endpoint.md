# ADR-008: Regional or global model endpoint

| Field | Value |
|---|---|
| Status | Superseded by [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md) |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md), [ADR-005](ADR-005-deployment-patterns.md) |

## Context

The platform's residency intent is US locations, with `us-east4` as the primary region. The `gcp.resourceLocations` organization policy restricts where resources are created, but it does not determine where a model request is processed. Agent Platform (Vertex AI) offers regional endpoints and a global endpoint. The global endpoint can improve availability, but it does not guarantee the processing location. Some models may be offered only on the global endpoint.

## Decision drivers

1. Requests processed in a known location by default.
2. Access to models that are offered only globally, when justified.
3. Residency trade-offs recorded and approved explicitly.
4. A single rule that every tenant follows.

## Options considered

| Option | Assessment |
|---|---|
| A. Regional endpoints only; global-only models are not allowed | Strongest residency position, but some models become unavailable |
| B. Global endpoint by default | Best availability, but no guarantee of processing location for any tenant |
| C. Regional endpoint by default; global endpoint only through a recorded exception | Residency by default, with deliberate exceptions |

Option A becomes reasonable if a tenant's data classification forbids any processing outside a known region.

## Decision

Use option C.

- Workloads call the `us-east4` regional endpoint wherever the model supports it.
- Each catalog entry records the endpoint the model uses.
- A model available only on the global endpoint requires its own decision record. That record states the residency trade-off, the data classifications the exception permits, and `ai-governance` approval.
- A resource-location policy is not treated as proof of model processing location.

## Consequences

**Positive**

- Model requests are processed in a known region by default.
- Every residency exception is visible and approved.

**Negative and accepted risks**

- Some models may be unavailable without an exception, or available later regionally than globally.
- Regional capacity may differ from global capacity, which affects 429 handling.
- The endpoint is part of each release's pinned model configuration. No organization policy is assumed to enforce it, so CI checks the configuration against the catalog entry.

## Implementation verification

This record is superseded. Current GA Gemini models are not offered on the `us-east4` regional endpoint, so [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md) replaces option C with a `us` multi-region default.

## Related decisions

- [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md): catalog entries record the endpoint and permitted classifications.
- [ADR-005](ADR-005-deployment-patterns.md): pattern availability varies by region.
