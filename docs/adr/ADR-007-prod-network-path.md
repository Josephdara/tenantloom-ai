# ADR-007: Prod network path under VPC Service Controls

**Status:** Accepted. Describes planned behavior; nothing here is implemented or verified.

## Context

A VPC Service Controls perimeter surrounds `jd-aip-prod`, and the threat model includes data exfiltration from prod. Google's Cloud Run guidance for VPC Service Controls sets several conditions:

- **Ingress.** Services must accept traffic only from internal sources, or from internal sources and Cloud Load Balancing. Setting ingress to `all` disables VPC Service Controls enforcement, and both `run.app` URLs and custom domains are subject to the perimeter.
- **Egress.** All outbound traffic must leave through a VPC, with firewall rules and DNS that keep Google API traffic on the restricted range.

The restricted range is not an allowlist of the perimeter's services. It serves every API that VPC Service Controls supports, including services the perimeter does not restrict. A workload holding credentials for an outside resource could reach it through such a service unless the perimeter also limits which APIs its network can reach.

Prod services still need callers from outside the perimeter: team clients, and the eval and canary jobs that run in nonprod (ADR-005). The CI identities that plan and apply Terraform also run outside the perimeter (ADR-004).

## Decision

1. **Ingress through a load balancer.**
   - An external Application Load Balancer in `jd-aip-prod` fronts each team's prod service through a serverless network endpoint group.
   - It uses a Google-managed certificate on a DNS name under the owner's domain.
   - Prod services set ingress to internal and Cloud Load Balancing, enforced by `run.allowedIngress` on `jd-aip-prod`.
   - The invoker IAM check stays on. Each service sets a custom audience for its load balancer hostname, so callers can request ID tokens for it.
2. **All egress through the VPC.**
   - Prod services use Direct VPC egress with all traffic routed through a VPC in `jd-aip-prod`, enforced by `run.allowedVPCEgress`.
   - The subnet has Private Google Access enabled.
   - A deny-all egress firewall rule is set after the default priority. A higher-priority rule allows TCP 443 to the restricted Google API range.
   - A Cloud DNS response policy resolves `*.googleapis.com` and `*.run.app` to `restricted.googleapis.com`.
   - Gemini is reached through the `us-east4` regional endpoint on that range.
3. **The network reaches only the perimeter's services.** The perimeter's VPC accessible services are set to its restricted services. Every Google API a prod workload calls must therefore be on the restricted list.
4. **Management and PAM ingress.** Ingress rules admit:
   - `sa-terraform` for all restricted services, `sa-terraform-plan` for read methods where a service supports method limits, and the break-glass account for recovery (ADR-004).
   - Each team's `<id>-developers` group for read methods on Cloud Run and Cloud Logging, the path for `<id>-prod-read` grants.
   - The platform admins group for the restricted services, the path for `platform-prod-admin` grants.

   PAM grants IAM roles only, so these rules provide the network path while IAM refuses access whenever no grant is active. Platform state generates the team rules from `tenants/`.
5. **Perimeter acceptance needs both kinds of test.** The perimeter runs in dry run until every documented flow shows zero violations. Enforcement is accepted only after tests also show the prohibited paths fail:
   - Internet egress from a prod container
   - A call to a supported Google API outside the restricted list, made with credentials that would otherwise allow it, which must fail with a VPC Service Controls denial rather than an IAM one
   - A write to a bucket in another project
   - An unauthenticated call
6. **Nonprod is outside the perimeter.** Dev and test services keep IAM-gated ingress without a load balancer, because they hold only synthetic data and are not perimeter members.

## Prior evidence

An earlier lab spike in a temporary project used the same egress pattern: a deny-all egress firewall and DNS mapped to the restricted range. It observed the following:

- An internet request timed out.
- The `us-east4` Agent Platform endpoint resolved to the restricted range.
- Gemini and Gen AI evaluation calls on regional endpoints succeeded.
- The Gen AI evaluation service rejected the `us` multi-region endpoint.

Those results predate this design and are not yet captured as published evidence.

## Consequences

- **More cost and DNS work.** The load balancer adds a fixed monthly charge even when idle, and the certificate needs a DNS name the owner controls.
- **More moving parts in prod:** a VPC, a subnet with Private Google Access, firewall rules, a DNS response policy, the load balancer, and its certificate.
- **Workload API calls are constrained.** Adding a Google API to a prod workload means adding it to the perimeter's restricted list first.
- **Eval and canary traffic go through the load balancer.** Canary requests aimed at the candidate revision need a route on it (ADR-005).
- **Some regional endpoints need extra plumbing.** A Google API whose regional endpoint is not served by the restricted range needs a Private Service Connect endpoint in the VPC, with its own DNS record and a firewall rule allowing its internal address. The earlier spike used one.
- **Management depends on ingress rules.** A missing or too narrow management rule blocks plans, applies, and drift checks against prod even when IAM allows them.

## Alternatives considered

- **Public ingress with IAM only.** Rejected. It disables VPC Service Controls enforcement for Cloud Run and leaves workload egress uncontrolled, so the perimeter would not address exfiltration.
- **Restricted range without VPC accessible services.** Rejected. The network could still reach every supported Google API, not only the perimeter's services.
- **Internal-only ingress.** Rejected for the lab. Callers and nonprod jobs would need private connectivity into the prod VPC.
- **Serverless VPC Access connector instead of Direct VPC egress.** Not chosen. Direct VPC egress needs no connector instances and meets the same egress constraint.

## Verification

- **Lab checks** (architecture, section 15):
  - With the perimeter enforced, an authorized caller and the nonprod eval job reach a prod service through the load balancer. Whether that path needs an ingress rule is not yet known. Fallback: an ingress rule for the load balancer path.
  - Prohibited paths fail from prod, including a supported API outside the restricted list.
  - Every Google API the starter service calls is on the restricted list.
  - Plans and applies against prod succeed through the management ingress rules.
  - A user with an active PAM grant reaches the granted prod resources through the perimeter and is refused after the grant expires.
- **Evidence to collect:** dry-run violation logs for each documented flow, and the results of each prohibited-path test under enforcement.
