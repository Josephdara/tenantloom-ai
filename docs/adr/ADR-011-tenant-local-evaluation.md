# ADR-011: Tenant-local evaluation jobs and dedicated environment identities

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-002](ADR-002-layered-provisioning-and-state.md), [ADR-004](ADR-004-delivery-pipeline-and-gates.md), [ADR-006](ADR-006-shared-prod-perimeter.md), [ADR-010](ADR-010-api-invocation-boundaries.md) |

## Context

A centrally maintained evaluation harness serves catalog and candidate evaluations, sandbox experiment evaluations, the test eval gate, and daily prod canary evaluations. Tenant golden datasets are stored in tenant-specific buckets in `jd-aip-eval`, and results are reported centrally.

An evaluation job needs three things: read access to a tenant's golden data, permission to call the service being evaluated, and permission to write results. Wherever those permissions sit, they must not let one tenant see or affect another, and they must not widen what a workload's runtime identity can do. Prod evaluation runs inside the prod perimeter, and prod images must come from the prod repository in `jd-aip-prod-shared`.

## Decision drivers

1. No evaluation identity with access across tenants.
2. Runtime identities do not gain evaluation permissions.
3. Evaluations run where the evaluated service runs, including inside the prod perimeter.
4. Results are attributed to the correct tenant and environment by IAM, not by self-reporting.
5. Results trace to the dataset, harness, release, and model configuration evaluated.

## Options considered

### Execution location

| Option | Assessment |
|---|---|
| A. Central execution in `jd-aip-eval` invoking tenant services | One place to run jobs, but its identity needs invocation and data access across every tenant, and it must reach into the prod perimeter |
| B. Jobs in each tenant environment project, using the shared harness image | No identity spans tenants; jobs run beside the service they test |

### Identity

| Option | Assessment |
|---|---|
| A. Reuse the workload runtime identity | Fewer accounts, but the runtime identity gains golden data access and result writes |
| B. A dedicated `sa-<tenant>-eval-<env>` per environment | Least privilege for both runtime and evaluation |

### Results storage

| Option | Assessment |
|---|---|
| A. One shared results table written by every tenant | A tenant could write rows attributed to another tenant |
| B. One table per tenant | Tenant attribution enforced, but environment attribution is self-reported |
| C. One table per tenant and environment in a platform-owned dataset, combined by a view | Each evaluation account writes only its own tenant and environment table |

## Decision

Use option B for execution location and identity, and option C for results storage.

| Evaluation activity | Execution location | Started by | Identity |
|---|---|---|---|
| Tenant sandbox experiment | Tenant sandbox project | Tenant developers, on demand | Tenant sandbox evaluation account, limited to models entitled to the sandbox |
| Tenant development evaluation | Tenant dev project | Tenant developers, on demand | Tenant dev evaluation account |
| Release eval gate | Tenant test project | Cloud Deploy verification task, as `sa-<tenant>-deploy-test` | Tenant test evaluation account |
| Daily prod canary evaluation | Tenant prod project | Cloud Scheduler in the prod project, as `sa-<tenant>-eval-prod` | Tenant prod evaluation account |
| Platform catalog and candidate evaluation | `jd-aip-eval` | `ai-platform-admins`, on demand | `sa-catalog-eval` |

- Each tenant environment has a Cloud Run job, `<tenant>-eval`, running the harness by digest as `sa-<tenant>-eval-<env>`, created by the factory in the second tenant pass. Developers execute sandbox and dev jobs with overrides limited to arguments, environment variables, task count, and timeout. Developers cannot execute test or prod jobs.
- The test eval gate executes the test job with the release ID and service URL and fails the rollout on failure. The deploy account has no `actAs` on the evaluation account, so it cannot redefine the job.
- In test and prod, the job uses Direct VPC egress with no internet route, reaching Google APIs and the service URL privately ([ADR-006](ADR-006-shared-prod-perimeter.md)).
- In prod, the job runs the harness by digest from the platform prod harness repository in `jd-aip-prod-shared`, published there by `sa-harness-build` and admitted by Binary Authorization through an allowlist pattern or a platform harness attestor ([ADR-004](ADR-004-delivery-pipeline-and-gates.md)). The factory references that digest when it creates the prod job, and no deploy account holds `actAs` on the evaluation account.
- Evaluation accounts hold Service Invoker in their own project; a custom evaluator role for model prediction, Experiments metadata writes, and Gen AI evaluation; read access to the tenant golden bucket; dataset metadata read on `eval_runs`; and append-only writes to their own tenant and environment table. The prod account also holds Jobs Executor on its own job, because it is the Scheduler identity.
- `sa-catalog-eval` holds Agent Platform User in `jd-aip-eval`, read access to the catalog dataset bucket and to golden buckets of tenants that opt in, and writes to a catalog results table. It has no tenant project roles.
- Results go to Experiments in the tenant environment project and to the tenant's table for that environment in the `eval_runs` dataset in `jd-aip-eval`. The platform core layer owns the dataset, tables, and combined view. Results tables hold scores and metadata only, never prompts, model outputs, or document content, so the prod evaluation path does not carry prod data out of the perimeter.
- Prod evaluation jobs cross the perimeter only through scoped egress rules: read-only access to the tenant's golden data bucket and writes to the tenant's prod results table.
- Tenant groups read their own results tables. `ai-platform-admins`, `ai-governance`, and `auditors` read the dataset and combined view.
- Evaluation evidence records the dataset and harness versions alongside the release and model configuration.

## Consequences

**Positive**

- No evaluation identity can reach more than one tenant, and IAM enforces both tenant and environment attribution.
- Workload runtime identities stay limited to serving.
- Prod evaluation pulls only promoted, attested images from inside the perimeter.

**Negative and accepted risks**

- Four evaluation accounts and four results tables per tenant.
- The evaluator role's exact permission list is set by verification in sandbox.
- The prod evaluation account doubles as the Scheduler identity.
- The harness image is shared by every tenant, so its build and supply chain affect all evaluations.
- The scores-only rule must be enforced in the harness and verified, because a harness change that wrote outputs to the results table would carry prod content out of the perimeter.

## Implementation verification

- The evaluator permission set, derived from denial audit entries in sandbox, and whether the Gen AI evaluation judge model must be entitled.
- The test verify task executes the job with overrides, a failing threshold fails the rollout, and the deploy account is denied updating the job.
- The Scheduler job runs the prod evaluation job under the enforced perimeter.
- An evaluation account is denied writing to another environment's or tenant's table, and a developer is denied executing the test job.
- Evaluation results contain no request or response content.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-002](ADR-002-layered-provisioning-and-state.md): ownership of evaluation jobs, storage, and grants across layers.
- [ADR-004](ADR-004-delivery-pipeline-and-gates.md): the eval gate, harness promotion, and daily canary evaluation in the release process.
- [ADR-006](ADR-006-shared-prod-perimeter.md): prod evaluations run inside the shared perimeter.
- [ADR-010](ADR-010-api-invocation-boundaries.md): evaluation identities as authorized callers.
