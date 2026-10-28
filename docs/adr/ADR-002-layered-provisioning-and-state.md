# ADR-002: Layered provisioning identities, tenant state split, and plan-to-apply integrity

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-001](ADR-001-environment-folders-with-tenant-projects.md), [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md), [ADR-004](ADR-004-delivery-pipeline-and-gates.md), [ADR-006](ADR-006-shared-prod-perimeter.md), [ADR-009](ADR-009-showback.md) |

## Context

TenantLoom AI provisions each tenant from a declaration file reviewed through a pull request. The target is onboarding with no manual steps beyond approvals. Four forces shape how that automation is structured:

1. **Isolation.** Tenant isolation is a core claim of the platform. No automation identity that runs for every tenant should be able to cross tenant boundaries or weaken platform controls.
2. **Resource sensitivity differs.** Provisioning touches tenant projects, shared projects (`jd-aip-ops`, `jd-aip-kms`, `jd-aip-eval`, `jd-aip-prod-shared`, and the service perimeters), and organization policy. Authority over a shared project or over organization policy reaches every tenant.
3. **Prod approval.** Changes that can affect prod or organization-wide controls need approval, and that approval must cover the exact change applied.
4. **Shared containers.** Some objects, such as perimeter membership lists and evaluation results, collect entries from every tenant. Two Terraform states managing the same object undo each other's changes.

A single provisioning identity holding every role needed would effectively be an organization administrator. Cloud Identity Groups Admin covers platform groups such as `ai-governance` and `auditors`; Organization Policy Administrator can be granted only at organization level and covers the whole baseline; and administrator roles in shared projects allow granting oneself access to every tenant's keys and data.

## Decision drivers

1. Smallest blast radius for every automation identity.
2. Approval before any change that can affect prod or organization-wide controls.
3. Each approval bound to the exact plan applied.
4. Exactly one owning Terraform state for every object.
5. Simplicity appropriate to a two-tenant lab.

Driver 5 gives way to drivers 1 to 3 wherever they conflict.

## Options considered

### Provisioning identity

| Option | Assessment |
|---|---|
| A. One factory identity with all roles | Simplest, but a defect or compromise in tenant automation reaches platform groups, organization policy, and every tenant's shared-project objects |
| B. One identity per layer: org, platform, and tenant | More identities and applies, but each identity's authority matches the resources it owns |

Option A becomes reasonable only if tenant isolation is not a claim the platform needs to make.

### Objects in shared projects

| Option | Assessment |
|---|---|
| A. Tenant states create their own entries in shared projects, and the tenant identity holds administrator roles there | Avoids state conflicts, but editing perimeter membership or creating keys and buckets requires authority over the whole container |
| B. The platform layer creates every tenant's shared-project objects from the tenant files | The tenant identity needs no roles in shared projects; onboarding becomes a sequence across layers |

### Tenant state layout

| Option | Assessment |
|---|---|
| A. One state per tenant, with prod changes detected by inspecting the plan | Fewest states, but depends on parsing plans and makes applies all-or-nothing |
| B. Three states per tenant: common, nonprod, and prod | Prod approval follows from the structure; cross-state references need a naming convention |
| C. One state per environment | Finest control, but too many states for the benefit at this scale |

### Apply coordination

| Option | Assessment |
|---|---|
| A. A queue service with ordering per tenant | Allows concurrency, but adds a component to build and operate |
| B. A platform-wide CI apply lock acquired by every apply build, with planning from the latest main | One apply at a time across every state; queue order does not matter because each plan starts from the latest main; needs a lock object and an interruption recovery procedure |

Terraform state locking alone is not option B. It protects each state separately, so applies to different states, such as an org apply and a tenant apply, could otherwise run at the same time.

Option A becomes reasonable when the number of tenants makes serialized applies too slow.

### Tenant groups

| Option | Assessment |
|---|---|
| A. The factory holds Groups Admin | Covers every group in the organization, including platform groups |
| B. The factory creates each tenant group as its initial owner, and individual users named in the tenant file manage membership | No organization-wide group authority; a group cannot own or manage another group, so managers are individual users |

## Decision

Use option B for every choice above.

### Layers and ownership

- **Bootstrap** is applied once by an administrator. It creates the bootstrap project, both state buckets, the saved plan bucket, the CI records dataset, the provisioning identities, and infrastructure CI. Its state then moves to the platform state bucket.
- **Org** (`sa-org`) owns folders, organization policies (including the `ai-platform` folder model default deny and per-project `vertexai.allowedModels`), audit configuration, the organization and folder log sinks, billing export, the central audit and billing datasets in `jd-aip-ops`, and tenant and platform budgets. `sa-org` holds Organization Policy Administrator and Billing Account Costs Manager.
- **Platform core** (`sa-platform`) owns the shared projects, perimeter definitions and membership lists, the `eval_runs` dataset with its per-tenant and per-environment tables and combined view, and the access review and showback datasets.
- **Platform per tenant** (`sa-platform`) owns each tenant's other objects in shared projects, including delivery accounts, pipelines, repositories, the prod repository and prod attestor in `jd-aip-prod-shared`, keys, and golden data buckets, in one state prefix per tenant.
- **Tenant** (`sa-factory`) owns tenant projects and their contents, the billing link, and tenant groups, in common, nonprod, and prod states per tenant. `sa-factory` holds Project Creator on the nonprod and prod folders and Billing Account User. As creator, it is Owner of the projects it creates; the security gate and access reviews treat that binding as expected.

The governing rule: each object has exactly one owning state. Objects in shared projects are created only by `sa-platform`, except the central audit and billing datasets, which the org layer owns because their writers, the log sinks and billing export, are org-layer objects. Objects in tenant projects are created only by `sa-factory`, and organization policies only by `sa-org`. The factory holds no roles in shared projects, no Groups Admin role, no budget role, and no organization policy or perimeter roles.

### Factory trust

`sa-factory` is trusted across all tenants. As creator, it is Owner of every tenant project, so it can impersonate, or grant itself the right to impersonate, any service account in those projects. That includes each tenant's evaluation accounts, which read golden data and write results in `jd-aip-eval`, and runtime accounts, which call models and use tenant keys. Holding no direct roles in shared projects removes the factory's own authority there, but not this indirect path. Tenant isolation therefore depends on the factory identity remaining uncompromised, and the design treats that as an accepted risk with these controls:

- `sa-factory` is used only by approved apply builds from main in infrastructure CI, and no human holds standing permission to impersonate it.
- The factory legitimately attaches tenant identities in only two cases: each `<tenant>-eval` Cloud Run job runs as its matching `sa-<tenant>-eval-<env>` account, and the prod Cloud Scheduler job authenticates as `sa-<tenant>-eval-prod`. Those attachments require `actAs` and count as expected only inside a recorded apply window, on a resource in that apply's plan, with that pairing.
- An audit query alerts on any access token, ID token, or signing request by `sa-factory` through the Service Account Credentials API, which provisioning never needs; on identity attachments outside the expected pairings or outside an apply window; on IAM policy changes to service accounts other than the ones the factory creates; and on any `sa-factory` activity outside a recorded apply window.
- Token requests appear only in IAM Data Access audit logs, so Data Access logging for `iam.googleapis.com` is enabled on the `ai-platform` folder alongside Agent Platform, and the folder sink copies it to the central audit dataset.
- Narrowing the factory's authority, for example by replacing the creator Owner binding with explicit roles or by denying service account impersonation to `sa-factory` through an IAM deny policy, is recorded as future hardening.

### Tenant groups

`sa-factory` creates `<tenant>-developers` and `<tenant>-release-approvers` with itself as initial owner. The tenant file names individual in-domain users as `group_managers`, who manage membership. `owners_group` remains the address for notifications and reports.

### CI separation

- Infrastructure CI runs in `jd-aip-bootstrap`, separate from workload CI in `jd-aip-ops`, so tenant workload builds cannot reach provisioning identities. Only infrastructure CI triggers can impersonate them.
- Pull request builds run as read-only plan identities. Repository-triggered builds read their build configuration from the commit being built, so a pull request must never run as an apply identity. Apply identities are used only by builds triggered from main that require approval. Main branch protection and control over who can edit infrastructure triggers are part of this boundary.

### Tenant input as a privilege boundary

Every layer reads the tenant files, so tenant input indirectly drives privileged identities. Schema validation enforces a strict tenant ID pattern, uniqueness against existing and decommissioned tenants, reserved names, enumerated environment and status values, permitted status transitions, catalog model IDs, and in-domain addresses. Every generated resource name is prefixed with the tenant ID.

### Onboarding sequence and approvals

Onboarding runs seven ordered applies, listed in [Approval and apply flow](../../architecture.md#6-tenant-provisioning-and-lifecycle). The tenant budget is created in the org step because its project filter needs project numbers from the earlier tenant steps. Three ordering rules matter:

1. The `ai-platform` folder default deny keeps new projects from using any model until the org layer applies their model policies.
2. A new prod project joins the perimeter before its delivery pipeline exists.
3. CMEK-protected data stores and evaluation jobs need a second tenant pass, because key access and image read access must name service agents that exist only after the projects are created.

Tenant nonprod applies need platform team approval. Every other step can affect prod or organization-wide controls and needs the prod-level Cloud Build approval. Governance approval of the pull request authorizes the intended change; approval before each apply authorizes the exact plan.

### Plan integrity, records, and state access

- Each apply uses two builds, because Cloud Build approval holds a build before any step runs. A plan build creates a fresh plan from the latest main and stores the saved plan and its hash in a restricted bucket that deletes files after 7 days. An approved apply build re-checks the hash and applies only that saved plan.
- Applying any plan invalidates other saved plans for the same state, and Terraform rejects a stale saved plan, so it must be planned and approved again. The check compares state versions, not live infrastructure. Terraform and provider versions are pinned, because a saved plan cannot be applied after an upgrade.
- After an approved apply, the apply build writes a CI record to `jd-aip-bootstrap`: build IDs, layer and state, commit, plan hash, approver and approval time, apply identity, timing, and outcome. Audit events are correlated with it by apply identity and build window, and its approver is checked against the `ApproveBuild` audit event.
- Applies run one at a time across the platform through a CI apply lock, because Terraform state locking protects each state separately and would allow applies to different states to overlap. The lock is an object in a dedicated bucket in `jd-aip-bootstrap`. After approval, every apply build, for every layer and state, creates the object with a create-only precondition, recording its build ID, layer, and state, and waits while another build holds it. It confirms it still holds the lock immediately before applying and deletes the object, with a generation match, when it finishes. Plan builds and nightly drift plans read state without taking the lock. Build timeouts bound how long a lock can be held, and an alert fires when the lock is older than the longest expected apply.
- An interrupted apply leaves the CI lock, and possibly a Terraform state lock, in place, and may leave a partly applied state. Recovery follows the runbook: confirm through the Cloud Build API that the holding build has ended, release the Terraform state lock and the CI lock under a `state-recovery` grant, which covers both the affected state bucket and the CI apply lock bucket, plan the affected state from the latest main, and apply only after fresh approval. The CI lock is what makes the apply build window in each CI record identify exactly one apply.
- State is split into two buckets by trust level: bootstrap, org, and platform state in one, tenant state in the other. `sa-factory` cannot read org or platform state. Layers do not read each other's state; they rely on naming conventions or look up deployed resources.
- Both buckets keep object versions. Human access uses the `state-recovery` PAM entitlement: object access on one named state bucket and on the CI apply lock bucket, up to 1 hour, approved by `ai-governance` with written justification. PAM does not allow self-approval. A restored state version must produce a plan with no unexplained changes before the next apply.

### Tenant lifecycle

The tenant file's `status` (`active`, `decommissioning`, `decommissioned`) drives offboarding, which applies the layers in reverse order in two phases. Shared assets a project restore would need are kept until the 30-day project recovery window has passed.

## Consequences

**Positive**

- The factory holds no direct authority over shared projects, perimeters, organization policy, platform groups, budgets, or org and platform state.
- Plan approval is enforced by Terraform's stale-plan check rather than by convention, and CI records tie each approval to the change it authorized.
- Prod approval follows from the state layout without parsing plans.

**Negative and accepted risks**

- Onboarding takes up to seven applies and several approvals. Approval wait counts against the one-hour provisioning target, so automation time and approval wait are measured separately.
- `sa-platform` concentrates authority over the shared projects and perimeters, and `sa-org` holds a billing-account role covering every budget. Both are used only by approved builds from main.
- `sa-factory` is trusted across all tenants. Through its creator Owner binding it can impersonate tenant service accounts and reach their access in shared projects, such as golden data and results in `jd-aip-eval`. Detection, not prevention, covers misuse.
- Serialized applies limit throughput, and an interrupted apply blocks every layer until the CI lock is recovered. Concurrent applies for independent tenants are future work.
- In a lab operated by one person, approval by a second persona account demonstrates the workflow without providing real separation of duties.
- The stale-plan check detects state changes, not drift made outside Terraform; short plan retention limits that window.

**Neutral**

- More Terraform roots and states to operate.
- Naming conventions replace cross-layer state reads, so resource names become part of the contract between layers.
- Tenant group managers are individual users named in the tenant file.

## Implementation verification

- `sa-factory` creates a tenant group under Cloud Identity Free as its initial owner and assigns individual managers. If this fails, the fallback is Groups Admin as a recorded risk with an access-review check on platform group changes.
- A saved plan applied after another apply to the same state is rejected with the pinned Terraform version and the state backend.
- An apply build reads its own approval result, writes its CI record, and the record joins to its audit events and `ApproveBuild` event.
- PAM refuses self-approval of `state-recovery`, and a restored state version passes the restore check.
- `sa-org` manages billing export and budgets with Billing Account Costs Manager.
- Two approved applies to different states started together never overlap: the second waits for the CI lock, and an apply build that does not hold the lock cannot apply.
- An apply interrupted mid-run leaves the CI lock, the lock-age alert fires, and the recovery runbook restores a clean plan and released locks using only a `state-recovery` grant, with no standing administrator access.
- What the creator Owner binding lets `sa-factory` do with tenant service accounts.
- IAM Data Access logs record Service Account Credentials API calls in tenant projects and reach the central audit dataset.
- An ordinary onboarding run, including evaluation and Scheduler job creation, raises no factory alert, while a token request by `sa-factory`, a job created with a mismatched identity, and `sa-factory` activity outside an apply window each raise one.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-001](ADR-001-environment-folders-with-tenant-projects.md): the tenant state split follows the environment folders.
- [ADR-003](ADR-003-catalog-and-entitlement-enforcement.md): entitlement enforcement uses the org layer defined here.
- [ADR-004](ADR-004-delivery-pipeline-and-gates.md): staged rollout of shared changes and per-tenant workload identities.
- [ADR-006](ADR-006-shared-prod-perimeter.md): the platform layer manages perimeter membership and `jd-aip-prod-shared`.
- [ADR-009](ADR-009-showback.md): the org layer owns budgets.
