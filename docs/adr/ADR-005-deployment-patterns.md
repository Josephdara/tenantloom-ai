# ADR-005: Deployment patterns

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md), [ADR-011](ADR-011-tenant-local-evaluation.md), [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md) |

## Context

Agent Platform (Vertex AI) offers several ways to consume a model, and they differ in who operates the serving infrastructure, how cost accrues, how capacity is obtained, and who controls version retirement. Every catalog entry records one of these patterns, so the platform needs a rule for which patterns are allowed where. TenantLoom AI aims to demonstrate the publisher, MaaS, and self-deployed patterns.

Self-deployed endpoints bill for dedicated hardware while deployed, whether or not they receive traffic, which makes a forgotten endpoint a direct cost risk.

## Decision drivers

1. Minimal infrastructure for tenants to operate.
2. Predictable and bounded cost.
3. Access to open and partner models where they are needed.
4. A demonstrated self-managed serving path.
5. Protection against idle dedicated hardware.

## Options considered

| Pattern | Use | Trade-off |
|---|---|---|
| Publisher model | Gemini models served by Google | No infrastructure and pay per token; dynamic shared quota with no reservation; Google sets version retirement |
| Model as a Service (MaaS) | Eligible open or partner models without managing hardware | Pay per token; availability depends on model and location |
| Self-deployed endpoint | Custom serving, or models not offered as MaaS | Dedicated hardware billed while deployed; the deployer owns scaling and patching |
| Provisioned Throughput | Reserved capacity for high, predictable volume | Requires a purchase commitment |

For demonstrating Gemma, three approaches were considered: MaaS only, which does not show self-deployed serving; a persistent self-deployed endpoint, which bills idle GPU time; and a short self-deployed run plus a short MaaS run, which shows both patterns at the cost of a few hours of GPU time.

## Decision

- **Publisher models** are the default for Gemini.
- **MaaS** is allowed for eligible open or partner models in the catalog.
- **Self-deployed endpoints** run only in `jd-aip-eval`. The evaluation workflow deploys, evaluates, and undeploys within one run. Each endpoint carries an expiry label, and a scheduled Cloud Run job undeploys endpoints past expiry. Tenant projects, including sandbox, set GPU serving quota to zero through Cloud Quotas. A future self-deployed catalog entry entitled to a sandbox would need a reviewed quota change.
- **Provisioned Throughput** is documented as the option for a tenant with reserved-capacity needs but is not purchased within this design.
- The initial catalog comparison uses the `team-docs` dataset and covers:
  - pinned Gemini Flash as the expected cost and latency default, planned as `gemini-3.8-flash`;
  - the pinned highest-capability Gemini model as the accuracy reference, planned as `gemini-4-argon`;
  - a small Gemma model self-deployed from Model Garden in `jd-aip-eval` on a single-GPU `us-east4` endpoint (the documented default class for a small Gemma is `g2-standard-12` with one NVIDIA L4);
  - a short run of the Gemma managed API as the MaaS demonstration, which stays a candidate while pre-GA.
- Exact model IDs and machine types are fixed when the catalog entries and runs are defined. The comparison is a set of hypotheses to evaluate, recorded in an eval report and a catalog decision.

## Consequences

**Positive**

- Publisher, MaaS, and self-deployed serving are each demonstrated.
- Tenant projects run no model-serving infrastructure, and GPU cost is limited to the hours of an evaluation run.

**Negative and accepted risks**

- Prod workloads can use only publisher or MaaS models. A tenant that needs custom serving in prod requires a new decision.
- Dynamic shared quota has no reservation, so workloads handle 429 responses with retries and backoff, and usage limits rely on instance caps, token ceilings, and budgets.
- Google controls retirement of publisher model versions, which drives the model upgrade process and daily canary evaluations.
- The two Gemma runs differ in model size and serving path, so they demonstrate the patterns rather than a like-for-like comparison.
- The Gemma managed API is pre-GA and may change or be withdrawn; another US-available open MaaS model would replace it.
- GPU serving quotas are set per region and per accelerator type, so every US region a tenant project can use must be covered.

## Implementation verification

- The Model Garden verified deployment configuration for the chosen Gemma in `us-east4`, and its `deploy` value.
- The endpoint that serves the Gemma managed API and its `predict` value.
- Zero quota for every serving accelerator in each usable US region, with a denied deployment attempt in a dev project.
- The cleanup job undeploys an expired endpoint.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md): catalog entries record the pattern, candidates stay in `jd-aip-eval`, and entitlements control access.
- [ADR-011](ADR-011-tenant-local-evaluation.md): catalog and candidate evaluations run in `jd-aip-eval`.
- [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md): endpoint location for each model.
