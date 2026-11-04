# ADR-006: Model deployment patterns

**Status:** Accepted. All three patterns are implemented and evaluated in sandbox. The self-deployed pattern was measured on the docs task only, because the support task's judge is blocked in sandbox. Results are in [evaluation evidence](../evidence/evaluation.md) and the [catalog evaluation report](../../catalog/reports/catalog-eval-v1.md).

## Context

A team can reach a model through Agent Platform in three ways:

- **Publisher.** Google's own models, such as Gemini, called through the Agent Platform API and billed per token.
- **Model as a Service (MaaS).** Open models, such as Gemma, run by Google behind a managed API and billed per token.
- **Self-deployed.** An open model from Model Garden deployed to an endpoint in the project, on machines the project pays for by the hour.

The platform's constraints shape which of these is usable and where:

- **Locations.** The `gcp.resourceLocations` organization policy limits resources to US locations. The catalog's Gemini models are not served on `us-east4`; they are called on the `us` multi-region endpoint. The Gemma MaaS model in the catalog, `gemma-4-26b-a4b-it-maas`, is served only on `global`: calls on `us` and `us-east4` return not found.
- **Evaluation service.** The Gen AI evaluation service is not available on `us`, and on `global` the location policy rejects it. It runs in `us-east4`, where the judge model it needs is not served.
- **Capacity.** Sandbox has quota for one L4 GPU for model serving in `us-east4`. Model Garden offers no L4 configuration for the small Gemma 4 variants, only larger GPUs or a 48-vCPU CPU machine. Gemma 3n E4B has a supported one-L4 configuration.
- **Allowlists.** `vertexai.allowedModels` controls managed models through the `predict` action and Model Garden deployments through the `deploy` action (ADR-001).

## Decision

1. **Publisher models are the default for team workloads.** They are called on the `us` endpoint, so processing stays in the US, and the allowlist grants `predict` only.
2. **MaaS models are evaluated in sandbox only for now.** The Gemma MaaS model runs on `global`, so its processing is not limited to the US. The catalog allows it as a sandbox candidate, and only for synthetic data, until it is served in a US location.
3. **Self-deployed models are a sandbox exercise with a short life.**
   - The catalog marks the model `self-deployed`, which generates a `deploy` allowlist entry rather than `predict`.
   - `sa-model-deploy`, impersonated by platform administrators, is the only identity that deploys. It holds Agent Platform User in sandbox only.
   - An hourly scheduled job undeploys any sandbox deployment older than four hours, so a forgotten endpoint stops billing.
   - The representative model is Gemma 3n E4B on one L4 in `us-east4`, because it is the only small Gemma with a supported configuration that fits the sandbox quota.
4. **The evaluation judge runs on `global`.** The evaluation service in `us-east4` calls `gemini-3.8-flash` on `global` through a `v1beta1` field, `allowCrossRegionModel`, that the public API reference does not document. If the field stops working, the harness scores the rubric itself with a pinned judge on `us`.

## Consequences

| Pattern | Where it runs | Cost model | Observed on the v1 development set |
|---|---|---|---|
| Publisher | `us` | Per token | `gemini-3.8-flash` at its default thinking level: p95 latency 8.8 s (docs) and 8.3 s (support). `gemini-4-argon` at thinking level `LOW`: 12.6 s and 13.7 s. |
| MaaS | `global` only | Per token | `gemma-4-26b-a4b-it-maas`: p95 latency 3.5 s and 3.4 s |
| Self-deployed | `us-east4` | Per machine hour while deployed | `gemma3n` on one L4, docs task only: field accuracy 0.976, schema validity 0.920 (fails), p95 latency 3.8 s |

- **Quality separated only the small self-deployed model.** The publisher and MaaS models scored full exact-match accuracy on the docs set and the maximum rubric score on the support set. `gemma3n` failed the schema gate, mostly by writing a currency symbol where the schema requires an ISO code. The v1 datasets are too easy to rank the larger models by quality; latency, location, and cost separate them.
- **Thinking dominates publisher latency.** In a separate sample, `gemini-3.8-flash` at thinking level `LOW` had a median latency of 1.4 s against 7.9 s at its default, with no loss of accuracy. Teams set the thinking level in their own release configuration.
- **MaaS trades location for speed.** It was the fastest pattern and passed every gate, but it runs outside the US multi-region.
- **MaaS models can be experimental.** The Gemma MaaS model's launch stage is experimental, so it can change without the notice period of a generally available model.
- **Self-deployment keeps an open model in a US region at MaaS-like latency.** `gemma3n` met the four-second gate in `us-east4`, but a model small enough for one L4 missed the quality gates the larger models passed.
- **Self-deployment carries operational weight.** It needs GPU quota, a deployment identity with broad sandbox permissions, endpoint expiry, and per-hour cost, which the managed patterns avoid. Quota does not guarantee capacity: the first deployment failed after about 25 minutes because no L4 machine was available in `us-east4`, and a retry succeeded. The `gcloud ai model-garden models deploy` command checks quota on the client first, which needs the Cloud Quotas API and quota and monitoring read for the deploying identity, so deployments call the Agent Platform deploy method directly instead.
- **A provider can withdraw a model from a project.** Gemini generation in sandbox began returning a policy rejection partway through the evaluation and stayed blocked, while Gemma MaaS and the other projects kept working. Keeping evaluation in its own project limited the effect to that project.

## Alternatives considered

- **Self-deploy Gemma 4 E4B.** Not chosen. Its supported configurations need an RTX PRO 6000 or H100 GPU, or a 48-vCPU CPU machine, and sandbox has no quota for any of them in `us-east4`.
- **MaaS only, with no self-deployment.** Not chosen. The self-deployed pattern is the only one that keeps an open model's processing in a US region, so it stays available as an option.
- **Score the rubric in the harness instead of the evaluation service.** Kept as the fallback. It uses documented APIs and keeps the judge on `us`, but moves scoring out of the evaluation service.

## Verification

- **Verified:** model locations, the evaluation service location, the cross-region judge, the generated allowlist entries including the `deploy` entry for `gemma3n`, a self-deployed deployment and undeployment, the expiry job's scheduled run, and the results above.
- **Pending:** the expiry job undeploying a real deployment, the self-deployed support task and the held-out runs blocked by the provider, and a harder dataset that can rank the patterns by quality.
