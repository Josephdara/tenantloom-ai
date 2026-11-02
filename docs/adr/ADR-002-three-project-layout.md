# ADR-002: Three-project layout

**Status:** Accepted. The three projects exist and are managed by CI (see [foundation evidence](../evidence/foundation.md)). Most controls described for each project are still planned.

## Context

TenantLoom AI needs sandbox, dev, test, and prod environments whose controls tighten toward production. Several of those controls are set per project:

- **Model allowlists.** `vertexai.allowedModels` applies to every principal in a project.
- **Perimeters.** VPC Service Controls perimeters contain projects, not individual services or teams.
- **Encryption and keys.** CMEK key rings and their service agent grants are per project.
- **Billing.** Each project needs a billing link, and the billing account has a limited number of them.

The platform also needs somewhere to run delivery tooling: Cloud Build, Cloud Deploy, Artifact Registry, the attestor, and Terraform state. It serves a small number of teams, and every environment holds synthetic data only.

## Decision

Three projects sit under the existing `ai-platform` folder:

| Project | Holds |
|---|---|
| `jd-aip-sandbox` | Shared exploration, Model Garden trials, and model evaluation |
| `jd-aip-nonprod` | Dev and test workloads, Terraform state, Cloud Build, Cloud Deploy, Artifact Registry, golden datasets, and audit and eval data |
| `jd-aip-prod` | Production workloads, the load balancer, CMEK keys, and the service perimeter |

- Dev and test share `jd-aip-nonprod` and are separated by service accounts, Cloud Run services, buckets, and IAM (ADR-003).
- Delivery and evaluation tooling stays in nonprod, so prod holds no build, delivery, or evaluation infrastructure (ADR-005).
- The Terraform state bucket lives in nonprod with the protections in ADR-004.
- Sandbox is shared by all teams on purpose. Team isolation applies to nonprod and prod.

## Consequences

- **One allowlist per project.** Teams that share a project share its model allowlist, so per-team model entitlements are enforced in CI (ADR-001).
- **Dev and test share a project boundary.** An IAM mistake in nonprod can expose one environment to the other. Both hold synthetic data, and the test gates rely on IAM separation rather than a project boundary.
- **Nonprod holds high-value tooling.** Terraform state, build triggers, and the attestor make nonprod a target. ADR-004 limits who can reach state, and the probe test shows that team build accounts are denied it.
- **The perimeter covers prod only.** Nonprod services are IAM-gated without a perimeter (ADR-007).
- **Costs are split by labels.** Environments that share a project are told apart by `env` labels, not by project.
- **Three billing links.** The layout fits a billing account with few free project links.

## Alternatives considered

- **Projects per team and environment.** Rejected. The project count grows with every team, each project needs its own billing link, allowlist, and budget, and the prod perimeter would need a project per team.
- **Four projects, with dev and test separated.** Not chosen. It duplicates delivery tooling or adds cross-project rules for it, and with synthetic data test needs no stronger boundary than dev.
- **A separate tooling project.** Not chosen. It adds a fourth project and cross-project grants for every pipeline. Keeping tooling in nonprod is acceptable with the state protections in ADR-004.
- **A single project.** Rejected. Prod would share an allowlist, keys, and network boundary with everything else, and a perimeter could not isolate it.
