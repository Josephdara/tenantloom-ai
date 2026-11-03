# ADR-001: Model access boundary

**Status:** Accepted. The catalog and the per-project allowlists are implemented; the model access tests and the CI entitlement check are not yet verified.

## Context

Teams reach Gemini and Model Garden models through Agent Platform. The platform must decide which models each environment allows and which models each team may use.

- **Allowlists are per project.** The `vertexai.allowedModels` organization policy applies to every principal in a project. Teams share `jd-aip-nonprod` and `jd-aip-prod` (ADR-002), so they share one allowlist in each.
- **Environments differ.** Sandbox evaluates candidates; nonprod and prod should only call approved models.
- **Entitlements differ by team and data.** A team's request file names the models it needs, and each model in the catalog lists the data classifications it is approved for.
- **Model calls need IAM too.** A caller needs permission to predict as well as an allowlisted model.

## Decision

1. **The catalog is the source of truth.** `catalog/catalog.yaml` lists each model with its publisher, status, deployment pattern, permitted data classifications, environments, eval report, approver, and retirement date.
2. **Terraform generates one allowlist per project from the catalog.**
   - Sandbox allows approved models and candidates.
   - Nonprod and prod allow approved models only.
   - Every entry is `predict` only, for example `publishers/google/models/MODEL:predict`.
   - Each project policy replaces the folder's deny-all, so a project without a catalog entry allows nothing.
3. **Team entitlements are enforced in CI.** A tenant request or release that names a model outside the team's entitlements, or a model not approved for the team's data classification, fails before build.
4. **Callers hold a minimal custom role.** The Gemini Invoker role in each project holds only `aiplatform.endpoints.predict`. Team runtime accounts get it in their own environment's project.
5. **New models enter through review.** A model is evaluated in sandbox as a candidate, then promoted by a pull request carrying its eval report and approved by `ai-governance`. Sixty days before a pinned model's retirement date, its replacement is evaluated and added; the old model leaves the allowlist once no team uses it or at retirement.

## Consequences

- **Accepted risk: runtime calls are not limited per team.** Within a project, any runtime account with the Gemini Invoker role can call any allowlisted model, including one its team is not entitled to. The CI check stops this at delivery time only. Every call is recorded in Data Access audit logs, so misuse is detectable afterward.
- **Upgrade path.** If per-team runtime limits become a requirement, a platform-owned model gateway can hold the only invoker grant and enforce entitlements per caller.
- **Catalog changes are policy changes.** Adding or retiring a model updates organization policy in up to three projects, so it goes through the same review and two approvals as any other platform change.
- **Starter entries are provisional.** The first catalog entries precede the catalog evaluation, so their eval reports and retirement dates are completed with that evaluation.

## Alternatives considered

- **A project per team.** Rejected in ADR-002. It would give each team its own allowlist at the cost of a project, billing link, and perimeter per team.
- **Per-team IAM conditions on model resources.** Not chosen. It would need conditions on publisher model resource names for every team and every model, and this design does not depend on that behavior.
- **A model gateway from the start.** Deferred. It adds a service in every model call path, and two teams do not need per-team runtime limits yet.

## Verification

- An allowlisted model call succeeds and a non-allowlisted call returns permission denied, in each project.
- A release naming a non-entitled model fails CI.
- Lab check 1: `sa-terraform` can set the project-level policies with its organization grant.
