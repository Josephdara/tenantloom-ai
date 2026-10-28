# ADR-007: Model Armor screening

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-002](ADR-002-layered-provisioning-and-state.md), [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md), [ADR-004](ADR-004-delivery-pipeline-and-gates.md), [ADR-005](ADR-005-deployment-patterns.md), [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md) |

## Context

Tenant workloads send untrusted content to models, which exposes them to prompt injection, jailbreak attempts, sensitive data leakage, harmful content, and malicious URLs. Model Armor screens prompts and responses for these categories, either through the sanitize API with a template or through floor settings that the Agent Platform (Vertex AI) integration applies to model calls in a project.

Floor settings do not apply to requests sent to multi-regional Agent Platform endpoints, and current GA Gemini models are offered only on multi-regional and global endpoints ([ADR-012](ADR-012-us-jurisdiction-model-endpoint.md)). The floor-setting integration covers non-streaming text `generateContent` calls and continues without screening when Model Armor is unavailable.

Screening can also block legitimate requests, so filter behavior needs tuning before blocking reaches prod. Screening logs contain full prompts and responses and are therefore sensitive.

## Decision drivers

1. Screening of every tenant model call, with any bypass detected.
2. Tuning against realistic data before blocking in prod.
3. Fail closed in test and prod.
4. Restricted handling of logs that contain prompt content.
5. Coverage for self-deployed models used in evaluation.

## Options considered

| Option | Assessment |
|---|---|
| A. Sanitize API calls from the workload, using a platform-created template | Works on every endpoint; tenant code controls whether the call happens |
| B. Project floor settings through the Agent Platform integration | Applies without application code, but not on multi-regional endpoints, and fails open |
| C. No Model Armor; rely on prompt design and output schema validation | Fewer moving parts, but no screening of inputs or outputs |
| D. A central model gateway that screens every call | Restores platform enforcement, but a new service to build and operate |

Option D becomes reasonable if screening must not depend on workload code.

## Decision

Use option A, delivered by the starter template, for every model call on every permitted endpoint, and keep option B as an additional safeguard for calls to regional endpoints.

- The tenant factory creates floor settings and a per-environment Model Armor template in `us-east4` on every tenant project.
- The starter template's model client sanitizes every prompt before the model call and every response before it is used, with the project template, whatever endpoint the catalog entry names: a regional endpoint, the `us` multi-region endpoint, or a global endpoint permitted by a recorded exception ([ADR-012](ADR-012-us-jurisdiction-model-endpoint.md)). The client has no code path that calls a model without screening.
- Floor settings also screen calls to regional endpoints. They are a second layer there, not a substitute for sanitization, because they do not apply to multi-regional endpoints, their global endpoint behavior is not documented, and they continue without screening when Model Armor is unavailable.
- Filters cover prompt injection and jailbreak, sensitive data, harmful content, and malicious URLs. Screening covers text; workloads send extracted text, not files or images.
- Sandbox and dev inspect only. Test and prod block on a match and reject the request when the sanitize call fails. Thresholds are tuned in test against golden datasets.
- Runtime accounts receive sanitize access to their own project's template. The Agent Platform service agent holds Model Armor User.
- For self-deployed models in evaluation, the harness calls the sanitize API with a template.
- In test and prod, Model Armor logs go to a restricted log bucket in the tenant's own project for that environment, excluded from the project's `_Default` bucket, with 30-day retention set by the factory. Only `auditors` can read them, through Logs View Accessor on the bucket's log view, in both test and prod. Prod logs stay inside the perimeter, and auditor reads cross it through group-based ingress. Sandbox and dev do not log prompt content. The bucket is not locked, so offboarding can delete it.
- Block counts feed a per-tenant log-based metric with spike alerts, and a spike is a rollback trigger ([ADR-004](ADR-004-delivery-pipeline-and-gates.md)). The security gate confirms injection attempts are blocked, and a log comparison flags model calls without a matching Model Armor record.

## Consequences

**Positive**

- Every tenant model call made through the starter template is screened on every permitted endpoint, and test and prod fail closed.
- False positives surface in test before prod.
- Prompt content is readable only by auditors.

**Negative and accepted risks**

- Screening depends on workload code, so a tenant can bypass it by changing code. This is detected, not prevented. A central gateway is the path to platform enforcement.
- Floor settings add a second layer only for regional calls; on the `us` and global endpoints, screening rests entirely on the sanitize calls.
- Blocking can reject valid prod requests.
- Model Armor logs contain prompt content and are deleted with the tenant project at offboarding; no copy is retained.

## Implementation verification

- Floor settings have no effect on `us` endpoint calls.
- For each endpoint type in use (regional, `us`, and any global exception), the sanitize-based block works for prompts and responses, and test and prod reject the request when a sanitize call fails.
- Whether per-request templates work on the `us` endpoint; if they do, they may replace separate sanitize calls.
- Sanitize permission on the runtime account and template logging settings.
- The Model Armor log name, the `_Default` exclusion, auditor access through the log view and the perimeter, and denial for a tenant developer.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-002](ADR-002-layered-provisioning-and-state.md): the tenant factory owns floor settings, templates, and log buckets.
- [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md): a central gateway remains the documented upgrade path.
- [ADR-004](ADR-004-delivery-pipeline-and-gates.md): block spikes trigger rollback, and the security gate tests injection handling.
- [ADR-005](ADR-005-deployment-patterns.md): self-deployed endpoints use the sanitize API.
- [ADR-012](ADR-012-us-jurisdiction-model-endpoint.md): the default endpoint is the `us` multi-region.
