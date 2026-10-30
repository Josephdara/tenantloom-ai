# ADR-005: Attested promotion with Cloud Deploy

**Status:** Accepted. Describes planned behavior; nothing here is implemented or verified.

## Context

Each team gets a Cloud Deploy pipeline with dev, test, and prod targets. Dev and test run in `jd-aip-nonprod`. Prod runs in `jd-aip-prod` behind a VPC Service Controls perimeter, and is reached only through a load balancer (ADR-007).

A release reaches prod only after these gates pass in test:

- **Eval**
- **Latency**
- **Security**

When they pass, `sa-attestor` signs a passed-test attestation with a KMS key, and Binary Authorization in prod admits only attested digests. Prod then rolls out as a canary with verification at each step.

Five questions shape the design:

- **Attestor location.** Where the attestor and its signing key live.
- **Enforcement.** Whether a deployer can bypass enforcement.
  - Binary Authorization on Cloud Run is a per-service setting, so without an organization policy a deployer can deploy with it off.
  - Breakglass can be requested through a manifest annotation or through the API's `breakglassJustification` field on any service update, and teams write their own manifests.
- **Eval location.** Where the eval and canary jobs run, given that they read the team's golden dataset and write results, both in nonprod.
- **Eval result isolation.** How each team's results are kept separate. BigQuery row-level policies filter reads but do not restrict writes.
- **Canary signal.** At a 10% traffic split, only about one request in ten reaches the candidate revision, so checks through the ordinary service address mostly measure the stable revision.

## Decision

1. **The attestor stays in nonprod.** The attestor, its Container Analysis note, the attestations, and the KMS signing key live in `jd-aip-nonprod`, next to the test gates. A platform-owned step runs as `sa-attestor` and signs only when all three test gates pass. Tenant triggers cannot use `sa-attestor`.
2. **Prod enforcement cannot be turned off or bypassed by deployers.**
   - The prod Binary Authorization policy requires that attestor.
   - `run.allowedBinaryAuthorizationPolicies` is set to `default` on `jd-aip-prod`, so every prod service must use it.
   - A custom organization policy constraint on `jd-aip-prod` rejects any service create or update that requests breakglass, through either the manifest annotation or the API field.
   - Emergency breakglass requires the break-glass administrator to lift that constraint. That policy change is logged and alerted, and each use is reviewed afterward.
   - Release CI also rejects rendered manifests that carry the breakglass annotation, and every breakglass event in the audit logs raises an alert.
   - Binary Authorization and Container Analysis stay off the perimeter's restricted service list, so admission against the nonprod attestor needs no perimeter rule.
3. **Eval jobs run in nonprod.** The eval harness and the daily canary eval run as Cloud Run jobs in `jd-aip-nonprod` as `sa-<id>-eval`. They read the dataset locally, and reach the team's prod service through the prod load balancer with `run.invoker`, like any other caller. Cloud Deploy verification steps, in test and at each prod canary step, start that job.
4. **One `eval_runs` table per team.** Each team's table sits in a shared nonprod dataset. Only that team's `sa-<id>-eval` can write it, and only the team's groups can read it. Tenant states own their own tables and grants. Platform state owns the governance union view and generates it from the active teams in `tenants/`, and `ai-governance` reads all teams' results through it.
5. **Cloud Deploy runs as the per-target deploy accounts.** Each Cloud Deploy target's execution account is `sa-<id>-deploy-<env>`. The prod ingress rule for delivery names only the `sa-<id>-deploy-prod` accounts. The egress rule for image pulls names prod's Cloud Run service agent and Artifact Registry in nonprod.
6. **The canary measures the candidate.**
   - At 10% and 50%, verification sends at least 50 requests directly to the candidate revision, for example through a revision tag, and also runs a mixed-traffic check through the service.
   - Pass criteria apply to the candidate's results.
   - Held-out items are sampled with replacement, and each request logs its item ID.
   - Prod rolls out at 10%, 50%, then 100%, and a Cloud Deploy repair rule rolls back when verification fails.
   - Each release record ties together the image digest, model ID, prompt version, generation parameters, eval run ID, and attestation.

## Consequences

- **Prod stays free of tooling.** Prod holds no build, delivery, or evaluation tooling, and the perimeter needs no egress rule for eval results.
- **Admission depends on nonprod.** New prod deploys depend on the attestor in nonprod being available. Serving does not, because running revisions are already admitted.
- **Attestation trust lives in nonprod.** Its integrity rests on keeping `sa-attestor` and the signing key limited to the platform-owned attestation step.
- **Emergency deploys are slower.** Breakglass needs the break-glass administrator to lift the constraint first, which trades speed in an emergency for a bypass deployers cannot use alone.
- **The canary is a stability check.** The held-out sets hold 30 and 15 items, so 50 candidate requests repeat items. The canary checks stability and error rate on known inputs. It is not a statistical guarantee that the true error rate is below 1%, and it does not measure generalization, which the test-stage eval covers.
- **Governance reads through a platform-owned view.** Onboarding or offboarding a team changes the view through a platform plan, so no tenant state can overwrite another team's entry.

## Alternatives considered

- **Attestor and attestations in prod.** Not chosen. `sa-attestor` would need an ingress rule to write into prod, and prod would hold delivery tooling. This remains the fallback if the admission check fails in the lab.
- **Breakglass limited only by detection.** Not chosen. Deployers could bypass enforcement and be caught only afterward. This remains the fallback if the custom constraint cannot cover both breakglass paths.
- **Eval jobs in prod.** Rejected. They would need egress rules to read the dataset and write results in nonprod, and prod would hold evaluation infrastructure.
- **One shared `eval_runs` table with row-level policies.** Rejected. Any team able to write the table could insert rows bearing another team's identifier.
- **Union view owned by the tenant module.** Rejected. One shared view in several tenant states would let each apply overwrite the others.
- **Canary checks only through the ordinary service address.** Rejected. At 10%, roughly 5 of 50 requests would reach the candidate.

## Verification

- **Lab checks** (architecture, section 15):
  - With the perimeter enforced, deploys checked against the nonprod attestor and image pulls by prod's Cloud Run service agent succeed.
  - Canary verification can target the candidate revision.
  - A prod deploy without Binary Authorization is refused, and the custom constraint refuses breakglass through both the annotation and the API field. Fallback: deployer breakglass accepted as a detected risk.
- **Evidence to collect:**
  - A release that fails a test gate is never attested and cannot be deployed to prod.
  - A failed canary rolls back automatically.
  - A release record matches its eval run.
  - One team's eval account cannot write another team's table.
