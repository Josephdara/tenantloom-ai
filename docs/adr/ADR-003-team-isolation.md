# ADR-003: Team isolation in shared projects

**Status:** Accepted. Planned; the tenant module that implements it is not yet built.

## Context

Teams share `jd-aip-nonprod` and `jd-aip-prod` (ADR-002). Sandbox is shared on purpose and holds synthetic data only. Within the shared projects, one team must not read another team's data or logs, act as its service accounts, invoke its services, or deploy into its pipeline.

Project boundaries do not separate teams here, so every boundary has to come from names, IAM, and resource ownership.

## Decision

1. **Every team has a stable ID.** The ID is 3 to 15 lowercase letters or digits, starting with a letter. CI enforces the format. The ID is used unchanged in file names, labels, groups, service accounts, and service names, and the length limit keeps `sa-<id>-deploy-prod` within the 30-character service account limit.
2. **Each team gets its own identities.** `sa-<id>-run-<env>`, `sa-<id>-eval`, `sa-<id>-build`, and `sa-<id>-deploy-<env>`, each scoped as in the identity matrix in the architecture. No team identity is shared.
3. **Each team owns its resources by name.** Its Artifact Registry repository, Cloud Deploy pipeline, dataset bucket, `eval_runs` table, log view, budget, and Cloud Run services carry the team ID, and IAM is granted on those resources rather than on the project wherever the service allows it.
4. **Invoker access is limited by service name.** Where a project-level grant is unavoidable, such as `run.invoker` for a team's callers, it carries an IAM condition on service names that start with `<id>-`.
5. **Team identities hold no project-level storage roles.** This keeps them out of the Terraform state bucket and other teams' buckets (ADR-004).
6. **Writes are isolated by ownership, not by filtering.** Each team writes its own `eval_runs` table. Row-level policies are not used, because they filter reads and do not restrict writes.
7. **Groups are created by an administrator.** Each team's `<id>-developers` and `<id>-release-approvers` groups exist before its onboarding pull request; Terraform only grants them access (ADR-004).
8. **Each team has its own Terraform state.** The tenant state owns only that team's slice, so changing or removing one team cannot touch another.

## Consequences

- **Naming is a security control.** A service or resource named outside the team prefix falls outside its team's conditions and grants. CI validation and the tenant module set every name, so teams do not choose them freely.
- **More resources per team.** Separate identities, repositories, tables, and log views multiply with each team. At two teams this is small.
- **Shared project limits remain shared.** Quotas, the model allowlist (ADR-001), and project-level settings still apply to every team in a project.
- **IAM mistakes cross teams.** A wrong grant in a shared project can expose another team. Isolation tests and the monthly access review, which flags cross-team bindings, are the controls.

## Alternatives considered

- **A project per team.** Rejected in ADR-002 for cost, billing links, and perimeter complexity.
- **Shared service accounts per environment.** Rejected. Any team could act as another team's runtime and read its data.
- **One shared `eval_runs` table with row-level policies.** Rejected. Any team able to write the table could insert rows under another team's ID.
- **Free-form team names.** Rejected. Names longer than the limit would break service account IDs, and inconsistent names would break the conditions that rely on prefixes.

## Verification

- Isolation tests show a developer from one team is denied the other team's data, logs, service accounts, and deployments.
- Lab check 10: a conditional `run.invoker` grant lets each team's callers invoke only that team's services.
- Lab check 12, repeated with a real team build account: it is denied the state bucket.
