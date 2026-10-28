# ADR-006: Shared prod perimeter with IAM isolation

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-001](ADR-001-environment-folders-with-tenant-projects.md), [ADR-002](ADR-002-layered-provisioning-and-state.md), [ADR-004](ADR-004-delivery-pipeline-and-gates.md), [ADR-010](ADR-010-api-invocation-boundaries.md), [ADR-011](ADR-011-tenant-local-evaluation.md) |

## Context

Prod tenant data needs protection against exfiltration even when credentials are stolen or IAM is misconfigured. VPC Service Controls perimeters restrict supported Google APIs, such as Agent Platform (Vertex AI), Cloud Storage, and BigQuery, to resources inside the perimeter unless ingress or egress rules allow otherwise.

Prod projects depend on shared projects. Provisioning runs from `jd-aip-bootstrap`. Deployments run from `jd-aip-ops`. Keys live in `jd-aip-kms`. Golden data and evaluation results live in `jd-aip-eval`. People occasionally need to investigate, administer, or audit prod.

Several products constrain placement. Cloud Run requires the image registry to be in the same perimeter as the deploying project. Binary Authorization recommends that the deployer, attestor, and attestation projects share the perimeter. Cloud Monitoring adds a project to a metrics scope only if it shares the scoping project's perimeter. Cloud Deploy under VPC Service Controls needs a private worker pool. Perimeters also carry lockout risk, because an incorrect rule can block delivery or administration.

## Decision drivers

1. An exfiltration boundary around all prod tenant data.
2. Every cross-boundary dependency explicit, scoped, and reviewable.
3. Onboarding a tenant without hand-editing perimeter rules; per-tenant entries are generated from the tenant files.
4. Rehearsal before enforcement.
5. Tenant isolation that holds inside the boundary.

## Options considered

### Perimeter structure

| Option | Assessment |
|---|---|
| A. One perimeter per tenant prod project | VPC Service Controls also separates tenants, but perimeters, rules, and bridges grow with every tenant |
| B. One shared perimeter for all tenant prod projects, with IAM isolation inside | Small and stable configuration; tenant separation inside depends on IAM |
| C. No perimeter, IAM only | Simplest, but no protection when credentials are stolen or IAM is wrong |

Option A becomes reasonable if tenants handle data whose separation must not depend on IAM alone.

### Placement of shared projects

| Option | Assessment |
|---|---|
| A. All shared projects outside, with an explicit rule for each path | Conflicts with the registry, attestor, and metrics scope placement requirements |
| B. Shared projects inside the prod perimeter | A project belongs to only one regular perimeter, and nonprod uses the same shared projects, so every nonprod path would cross into the prod perimeter and tenant workload builds would run inside it |
| C. Every shared project split by environment | A separate prod evaluation project duplicates golden data, and keys and CI gain little from a split |
| D. Shared projects outside, plus a prod-only project inside for objects the products require to share the perimeter | One more project and a promotion step; prod still runs the tested digest because images are copied by digest |

### Ingress identities

| Option | Assessment |
|---|---|
| A. Named identities generated from the tenant files | Each rule admits only the identities that need it; onboarding changes generated lists, not rule structure |
| B. Any service account from a source project | Admits every identity in the source project, and depends on how the perimeter attributes Cloud Build and Cloud Deploy requests to a source project, which is not documented |

### Human access

| Option | Assessment |
|---|---|
| A. Ingress rules referencing groups, read-only methods where supported | Strong identity binding through the groups eligible for prod PAM entitlements and the `auditors` group |
| B. An access level based on device or network | No group list, but weaker identity binding and more Access Context Manager configuration |

### Workload outbound traffic

The perimeter restricts Google API access, but it is not a general outbound firewall. A workload with internet access could send prod content to any external destination.

| Option | Assessment |
|---|---|
| A. Default internet egress, with the risk accepted | No network to build, but a compromised workload can send data anywhere, so the exfiltration claim would cover Google API data paths only |
| B. Direct VPC egress for all traffic in test and prod, no internet route, Google APIs reached privately | Keeps the exfiltration claim; adds a VPC, private DNS, and Private Service Connect endpoints per test and prod project, with their running cost |

## Decision

Use a shared enforced perimeter (structure B), keep the general shared projects outside it with a prod-only project inside (placement D), admit named identities generated from the tenant files (ingress A), reference groups for human access (human access A), and remove internet egress from test and prod workloads (outbound B).

- The enforced perimeter contains every tenant prod project and `jd-aip-prod-shared`, and restricts every supported service the prod projects use. A dry-run perimeter contains every tenant test project; its violation logs are reconciled against the path table before rules are enforced in prod.
- `jd-aip-prod-shared` holds per-tenant prod image repositories, per-tenant prod Binary Authorization attestors with their signing keys and attestations, and the prod metrics scope. The prod predeploy task copies each tested image by digest into the tenant's prod repository and signs the prod attestation ([ADR-004](ADR-004-delivery-pipeline-and-gates.md)). Each tenant's prod repository is readable only by that tenant's Cloud Run service agent.
- The platform core layer generates membership and per-tenant rule identities from the tenant files.
- Each cross-boundary dependency has its own rule, listed in the architecture's cross-boundary path table: ingress for prod deploy accounts (deploy, verification, and promotion) from the `jd-aip-ops` private worker pool, for `sa-harness-build` publishing the harness to the prod harness repository, for provisioning identities from `jd-aip-bootstrap`, and for PAM-eligible groups and `auditors`; egress for key operations to `jd-aip-kms`, golden data reads and evaluation result writes to `jd-aip-eval`, and IAM policy exports if dry run shows one is needed.
- Rules name specific identities, target projects, and services, and use read-only methods where the path only reads and the service supports method selectors. Cloud KMS rules allow all methods, because Cloud KMS does not support method selectors.
- Only three Google API paths move prod data out: audit logs, IAM policy exports, and evaluation results. Evaluation results contain scores and metadata only. Image pulls, attestation checks, and metrics stay inside the perimeter. The folder aggregated audit sink is expected to need no egress rule.
- Workloads have no other network path out. In each tenant test and prod project, the factory creates a VPC with one `us-east4` subnet, and the tenant service and evaluation job use Direct VPC egress for all traffic; the org layer enforces this with `run.allowedVPCEgress` set to `all-traffic`. The VPC has no Cloud NAT or external IP addresses, and an egress firewall denies every destination except private Google API addresses.
- Global Google API endpoints are reached through Private Google Access with private DNS resolving to the `restricted.googleapis.com` addresses, which serve only services that VPC Service Controls supports. The `us` multi-region Agent Platform endpoint and the `us-east4` Model Armor endpoint, which Private Google Access does not serve, are reached through Private Service Connect endpoints with private DNS.
- Test mirrors prod, so the dry-run perimeter and the security gate exercise the same egress controls. Sandbox and dev keep default internet egress because they hold synthetic or public data only.
- Inside the perimeter, tenants are separated by project IAM, per-tenant service accounts, per-tenant key rings, per-tenant prod repositories and attestors, and restricted shared-service permissions.
- Cloud Run ingress is `all`, so the perimeter does not restrict calls to a service's URL. Invocation is authorized by IAM ([ADR-010](ADR-010-api-invocation-boundaries.md)).
- Access policies are organization-level resources, so the break-glass account can change perimeters from outside them; this is verified by drill before enforcement.

## Consequences

**Positive**

- One exfiltration boundary covers every tenant's prod data, for both Google API access and workload network egress.
- Every dependency that crosses it is named, scoped, and reviewable, and egress paths carry an explicit data rule.
- Onboarding changes generated membership and identity lists, never rule structure.

**Negative and accepted risks**

- VPC Service Controls does not separate tenants inside the perimeter. IAM is the tenant boundary there, so access reviews and persona tests must verify it.
- One more shared project and a promotion step for prod images.
- Each test and prod project carries a VPC, private DNS zones, and Private Service Connect endpoints, which have a running cost and must exist before the first deployment. Workload code cannot call any external service; a tenant that needs one requires a new decision.
- Prod data can still leave through responses to authorized callers; the egress controls do not limit what a workload returns to a caller IAM admits.
- The test dry-run perimeter does not rehearse the prod image path, because test pulls from `jd-aip-ops`.
- With ingress `all`, the perimeter does not protect service invocation. Prod ingress `internal` is the hardening option once callers run inside a VPC.
- Restricting every supported service is likely to surface paths not yet in the table. The test perimeter must run in dry run long enough to capture deployments, evaluations, and access reviews.
- Perimeter changes can lock out delivery or administration. Dry-run rehearsal, nonprod-first staging, and the break-glass account mitigate this.

## Implementation verification

- Infrastructure CI and Cloud Deploy private-pool requests match the generated rules; if source-project matching fails, rules match the named identities from any origin.
- Cloud Deploy in `jd-aip-ops` rolls out to a prod Cloud Run target through the private pool under enforcement.
- Promotion keeps the image digest unchanged, Cloud Run pulls from `jd-aip-prod-shared`, and Binary Authorization admits the attested image and rejects an unattested one.
- The service agents used for CMEK key operations match the generated egress list.
- Model Armor and the `us` multi-region Agent Platform endpoint work under enforcement through Private Service Connect.
- From test and prod, the service and evaluation job reach every Google API they use and the prod service URL through the private path, and a request to an external HTTPS destination is denied.
- `run.allowedVPCEgress` rejects a revision or job without all-traffic VPC egress.
- The folder audit sink and access-review export run without violations, and an unlisted path is denied.
- The break-glass account changes the enforced perimeter from outside it.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-001](ADR-001-environment-folders-with-tenant-projects.md): prod projects are grouped in the `prod` folder.
- [ADR-002](ADR-002-layered-provisioning-and-state.md): the platform layer owns perimeters, their membership, and `jd-aip-prod-shared`.
- [ADR-004](ADR-004-delivery-pipeline-and-gates.md): prod promotion copies images and signs attestations inside the perimeter.
- [ADR-010](ADR-010-api-invocation-boundaries.md): service invocation is governed by IAM, not the perimeter.
- [ADR-011](ADR-011-tenant-local-evaluation.md): prod evaluation jobs read golden data and write results across the boundary.
