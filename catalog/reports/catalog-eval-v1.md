# Catalog evaluation report: dataset v1

This report compares the catalog's models on the v1 evaluation datasets. Every number below comes from a row in the `catalog_eval.eval_runs` table in `jd-aip-sandbox`, identified by its run ID, and each run's per-item report is stored next to the dataset split it read. How the evaluation works is described in [architecture section 11](../../architecture.md#11-mlops-and-evaluation), and the checks behind it are in [evaluation evidence](../../docs/evidence/evaluation.md).

**Recommendation:** no catalog change from this evaluation. The v1 datasets separate only the self-deployed Gemma 3n model, which fails schema validity, and five held-out runs could not complete. A harder dataset and complete held-out runs are needed before any candidate is promoted.

## Setup

| Item | Value |
|---|---|
| Harness image | `us-east4-docker.pkg.dev/jd-aip-nonprod/platform/eval-harness@sha256:54eb1c9b4e395965dcce553a479c1c96f76228e70e0a91b82307ab0c5e13d089`, built from commit `85b265889ba5830a159999e3b9435b5539193c8c`, harness version 0.1.0 |
| `docs` dataset v1 | Development split: 50 items, SHA-256 `c94d7c73816eebfd3fb8643e58c0d58e425a323a4e9ee8265da3fee4c17145ed`. Held-out split: 30 items, SHA-256 `e9bee498242e90f5078f627364f3fb0a20e44fa41663b835d146f979c634ebc2` |
| `support` dataset v1 | Development split: 25 items, SHA-256 `6846966811645ea9e8a0cbe053c5dbd34bae33446daece61ecbe7d9c58f96790`. Held-out split: 15 items, SHA-256 `98ad7391896197990ce929ef53121f97704a601caf598a8a79e658586d737f18` |
| Prompts | `docs-extract-v1`, `support-summarize-v1` |
| Rubric and judge | `support-faithfulness-v1`, scored by `gemini-3.8-flash` on `global` through the evaluation service in `us-east4` |
| Exact match | Gen AI evaluation service in `us-east4` |
| Thresholds | `docs`: field accuracy at least 0.9. `support`: rubric mean at least 4.0. Both: schema validity 1.0 and p95 latency at most 4.0 s |

The dataset hashes match the committed manifests in `eval/datasets/`.

| Model | Pattern | Location | Generation parameters |
|---|---|---|---|
| `gemini-3.8-flash` | Publisher | `us` | Temperature 0, JSON output, up to 2048 output tokens, default thinking level |
| `gemini-4-argon` | Publisher | `us` | Temperature 0, JSON output, up to 4096 output tokens, thinking level `LOW` |
| `gemma-4-26b-a4b-it-maas` | MaaS | `global` | Temperature 0, up to 2048 output tokens |
| `gemma3n` (`gemma-3n-e4b-it`) | Self-deployed | `us-east4` | Temperature 0, up to 1024 output tokens, one NVIDIA L4 on `g2-standard-12`, Model Garden's default serving container |

## Results: development split

| Task | Model | Quality | Schema validity | p95 latency | Passed | Run ID |
|---|---|---|---|---|---|---|
| docs | `gemini-3.8-flash` | Field accuracy 1.000 | 1.000 | 8.795 s (fails) | No | `28391bc93d9b4029af7b52ebae5545a5` |
| docs | `gemini-4-argon` | Field accuracy 1.000 | 1.000 | 12.629 s (fails) | No | `def57b44104942b0bdbb26ac886cded4` |
| docs | `gemma-4-26b-a4b-it-maas` | Field accuracy 1.000 | 1.000 | 3.474 s | Yes | `86e101bdcf4046939e12d889602ecfff` |
| docs | `gemma3n` | Field accuracy 0.976 | 0.920 (fails) | 3.788 s | No | `d123c7ba165e4cd6a6a48760398e8945` |
| support | `gemini-3.8-flash` | Rubric mean 5.000 | 1.000 | 8.336 s (fails) | No | `6fa68938dab849c287f6e52a6cffa757` |
| support | `gemini-4-argon` | Rubric mean 5.000 | 1.000 | 13.684 s (fails) | No | `f1712c503fcc477686a25ffbf9f9adc7` |
| support | `gemma-4-26b-a4b-it-maas` | Rubric mean 5.000 | 1.000 | 3.392 s | Yes | `7bdc85baba554605b08ec1cece746d90` |

No run had an item error. Every model call finished normally, three needed one retry, and every run was also recorded in Agent Platform Experiments. The `gemma3n` support task was not run, because its judge is a Gemini model and Gemini generation is blocked in sandbox, as described under the held-out results.

## Results: held-out split

| Task | Model | Outcome | Run ID |
|---|---|---|---|
| docs | `gemma-4-26b-a4b-it-maas` | Field accuracy 1.000, schema validity 1.000, p95 latency 37.019 s (fails) | `81dd590d35e747b289687ea8ad5db8f1` |
| docs | `gemma3n` | Field accuracy 0.980, schema validity 0.900 (fails), p95 latency 3.753 s | `83f7ccea96c0476d8492ffefd7667e47` |
| docs | `gemini-3.8-flash` | Not completed: all 30 model calls rejected by the provider | `39f9e678a4ba46699f133228862381c5` |
| docs | `gemini-4-argon` | Not completed: all 30 model calls rejected by the provider | `db614aee56e1476784bfd7dc971d7afe` |
| support | `gemini-3.8-flash` | Not completed: all 15 model calls rejected by the provider | `4f8bbbdb927b4bf68f2ebe6ed71b19e7` |
| support | `gemini-4-argon` | Not completed: all 15 model calls rejected by the provider | `1aff4c610e1b4213859b46a267df372b` |
| support | `gemma-4-26b-a4b-it-maas` | Not completed: summaries were schema-valid, but all 15 judge calls were rejected by the provider | `e4b0668263334b4faec1b7b174e57074` |

Between the development and held-out runs, Agent Platform began rejecting every Gemini generation request in `jd-aip-sandbox` with HTTP 403 and the message "Request rejected in accordance with our terms of use and policies." The judge is a Gemini model, so judged runs failed too. The harness recorded each failed item and still wrote the report and the record, so these rows are kept as an accurate account of the attempt, not as results. Their quality metrics are zero and their latency reads 0.0 s because no call succeeded.

## Findings

- **The v1 datasets are too easy for the larger models.** The publisher and MaaS models extracted every invoice field correctly, and the judge gave every summary the maximum score. The datasets show that the pipeline works but cannot rank those models by quality.
- **The small self-deployed model makes real extraction errors.** On the development split, `gemma3n` wrote `CA$` instead of the ISO code `CAD` on four Canadian-dollar invoices, which the output schema rejects, and read two dates month first. One of those dates, `docs-0031`, is clear from its day-first due date; the other, `docs-0006`, is ambiguous in its text. The held-out split had three schema failures; its per-item report is readable only by the evaluation account, so their causes were not inspected.
- **Latency separates the models.** Only the MaaS model and the self-deployed `gemma3n`, which keeps processing in `us-east4`, met the four-second p95 target. Both Gemini models ran with thinking enabled; in a separate sample, `gemini-3.8-flash` at thinking level `LOW` had a median latency of 1.4 s against 7.9 s at its default, with equal or better accuracy.
- **The held-out Gemma run was much slower than its development run.** Its p95 latency rose from 3.5 s to 37.0 s on the same model and settings. The cause is not known.
- **The support data has a known bias.** `gemini-4-argon` wrote the synthetic tickets and reference summaries, so it may score better on text in its own style.

## Next evaluation

1. A v2 dataset with more varied and harder invoices, weaker reference summaries mixed in, and a rubric version with clearer distinctions near the top.
2. A check that the judge scores deliberately poor summaries low.
3. Complete held-out runs once Gemini generation works in sandbox again, run one at a time.
4. The `gemma3n` support task, once its judge works in sandbox again.
