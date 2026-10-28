# ADR-010: Tenant API invocation boundaries and temporary production human access

| Field | Value |
|---|---|
| Status | Accepted |
| Implementation | Planned |
| Deciders | Platform team (`ai-platform-admins`), approved by `ai-governance` |
| Related | [ADR-002](ADR-002-layered-provisioning-and-state.md), [ADR-004](ADR-004-delivery-pipeline-and-gates.md), [ADR-006](ADR-006-shared-prod-perimeter.md), [ADR-011](ADR-011-tenant-local-evaluation.md) |

## Context

Each tenant exposes its workload as a Cloud Run service. Calling a service is a different permission from deploying it, administering it, or viewing its project. Domain restricted sharing blocks `allUsers` bindings, but that alone does not prove a service requires authentication.

Several kinds of caller need access: tenant developers testing their own services, application identities that use a service, and evaluation and smoke-test identities that run release checks. Prod has a goal of no standing human roles, but people occasionally need to test a prod service directly, and release approvers need to approve prod releases.

Cloud Run does not support resource-name IAM conditions, so a binding cannot name a service before it exists, and services are created by the delivery pipeline after provisioning. `roles/run.servicesInvoker` allows calling services only; `roles/run.invoker` also allows executing jobs. PAM entitlements apply at organization, folder, or project level, not to a single service. With Cloud Run ingress `all`, the prod perimeter does not restrict calls to a service's URL.

## Decision drivers

1. Every service requires IAM authentication and explicitly authorized callers.
2. Invocation is separate from read-only and administrative access, and from job execution.
3. No tenant can call another tenant's services unless explicitly approved.
4. Human invocation in prod is temporary and approved; no standing human roles on prod projects.
5. Evaluation and smoke-test identities can reach only their own tenant's services in their own environment.

## Options considered

### Granularity and timing

| Option | Assessment |
|---|---|
| A. Project-level `roles/run.invoker` for groups | Exists before services, but includes job execution |
| B. Service-level bindings set by the deploy step | Needs Cloud Run Admin in a tenant-influenced pipeline, which could grant invocation to any identity |
| C. Service-level bindings applied by Terraform after first deploy | Ordering dependency, failed plans for missing services, drift when services are renamed |
| D. Project-level `roles/run.servicesInvoker` in each single-tenant environment project, with service-level bindings only for approved cross-tenant callers | Tenant-scoped by project structure, bindings exist before services, no job execution rights |

### Human invocation in prod

| Option | Assessment |
|---|---|
| A. Standing invoker access for developers | Convenient, but conflicts with no standing human access |
| B. No human invocation in prod | Strict, but blocks direct diagnosis |
| C. Temporary, approved, expiring access through PAM | Meets the goal at project scope |

### Release approver access

| Option | Assessment |
|---|---|
| A. Standing prod read-only plus Cloud Deploy Approver | Conflicts with no standing human roles on prod |
| B. Cloud Deploy Approver on the tenant pipeline conditioned on the prod target, no prod project roles | Approval needs no prod project access; gate results live outside prod |
| C. Approver role granted through PAM for each release | Stronger, but adds a second approval loop to every release |

### Ingress

| Option | Assessment |
|---|---|
| A. `all` with IAM authentication everywhere | Works for every current caller; the perimeter does not restrict invocation |
| B. `internal` in prod | The perimeter protects invocation, but needs an internal path for gate tasks and human testing |

## Decision

Use granularity D, human option C, release approver option B, and ingress A.

- The factory grants `roles/run.servicesInvoker` at project level in each tenant environment project to: tenant developers in sandbox, dev, and test; the environment's evaluation account in every environment; and application service accounts in the tenant file's `callers` list, which must belong to the same tenant and environment. The pilots declare none.
- Deploy accounts can invoke their own target's services through Cloud Run Developer; the dev smoke test uses this.
- An approved cross-tenant caller receives a binding on the named service only, after the service exists, with `ai-governance` approval.
- The org layer enforces `run.managed.requireInvokerIam`. Deploy accounts lack `run.services.setIamPolicy`, so they cannot disable the invoker check either.
- Temporary prod human invocation uses the PAM entitlement `<tenant>-prod-invoke`: Service Invoker on the tenant prod project, requested by tenant developers, approved by tenant release approvers with written justification, for up to 1 hour. It is separate from `<tenant>-prod-investigate`. PAM does not allow self-approval.
- Release approvers hold no role on prod projects. Their standing authority is Cloud Deploy Approver on their tenant's pipeline conditioned on the prod target, Cloud Deploy Viewer on that pipeline, a rollback-only custom role on the pipeline and prod target, and read access to their tenant's results tables. They review test verification results in Cloud Deploy and the tenant's test results in `eval_runs`.
- Ingress is `all` in every environment. Ingress `internal` in prod is the hardening option once application callers run inside a VPC.

## Consequences

**Positive**

- Bindings exist before services, so there is no ordering problem or deploy-time IAM.
- Invokers cannot start evaluation jobs.
- No standing human roles on prod projects; the only standing human prod access is auditor read on restricted Model Armor log views.

**Negative and accepted risks**

- An authorized caller can reach every service of its tenant in that environment. A tenant that needs different callers per service adds service-level bindings as a recorded exception.
- With ingress `all`, the perimeter does not protect invocation, so IAM is the only invocation control.
- Deploy accounts can invoke their own target's services.
- In a one-person lab, persona approval demonstrates the workflow without real separation of duties.

## Implementation verification

- A developer persona invokes its own dev service and is denied on the other tenant's dev service, its own prod service, and the test evaluation job.
- A revision with the invoker check disabled is rejected, through the pipeline and directly.
- A `<tenant>-prod-invoke` grant allows a call, and the call is denied after expiry.
- A release approver with no prod project roles approves its own tenant's prod rollout and is denied the other tenant's, and can see pipeline and job state.

See [Implementation verification](../../architecture.md#17-implementation-verification).

## Related decisions

- [ADR-002](ADR-002-layered-provisioning-and-state.md): the tenant factory owns bindings in tenant projects, and the platform layer owns grants on shared-project objects.
- [ADR-004](ADR-004-delivery-pipeline-and-gates.md): release approval and rollback in Cloud Deploy.
- [ADR-006](ADR-006-shared-prod-perimeter.md): with ingress `all`, the perimeter does not govern invocation.
- [ADR-011](ADR-011-tenant-local-evaluation.md): evaluation identities as authorized callers.
