import json
import math
import re

from .api import api_host, post_json

FENCE = re.compile(r"^```(?:json)?\s*(.*?)\s*```$", re.DOTALL)


def parse_output(text):
    stripped = text.strip()
    match = FENCE.match(stripped)
    if match:
        stripped = match.group(1)
    try:
        value = json.loads(stripped)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def schema_valid(output, schema):
    from jsonschema import Draft202012Validator

    return output is not None and Draft202012Validator(schema).is_valid(output)


def p95(values):
    if not values:
        raise ValueError("no values")
    ordered = sorted(values)
    return ordered[math.ceil(0.95 * len(ordered)) - 1]


def field_pairs(output, labels, fields):
    output = output or {}
    return [(str(output.get(field, "")).strip(), str(labels[field]).strip()) for field in fields]


def exact_match_scores(sess, project, location, pairs):
    url = f"{api_host(location)}/v1/projects/{project}/locations/{location}:evaluateInstances"
    body = {
        "exactMatchInput": {
            "metricSpec": {},
            "instances": [{"prediction": prediction, "reference": reference} for prediction, reference in pairs],
        }
    }
    values = post_json(sess, url, body)["exactMatchResults"]["exactMatchMetricValues"]
    if len(values) != len(pairs):
        raise ValueError(f"evaluation service returned {len(values)} scores for {len(pairs)} fields")
    return [float(value.get("score", 0.0)) for value in values]


def judge_score(sess, project, location, judge, template, instance):
    # The judge model is not served in the evaluation service's region, so the request names it on the global
    # endpoint and allows a cross-region call; this v1beta1 field is not in the public API reference.
    url = f"{api_host(location)}/v1beta1/projects/{project}/locations/{location}:evaluateInstances"
    body = {
        "pointwiseMetricInput": {
            "metricSpec": {"metricPromptTemplate": template},
            "instance": {"jsonInstance": json.dumps(instance)},
        },
        "autoraterConfig": {
            "autoraterModel": f"projects/{project}/locations/{judge['location']}/publishers/google/models/{judge['model']}"
        },
        "allowCrossRegionModel": True,
    }
    result = post_json(sess, url, body)["pointwiseMetricResult"]
    score = float(result["score"])
    if not 1.0 <= score <= 5.0:
        raise ValueError(f"judge score {score} is outside the 1 to 5 rubric")
    return score, result.get("explanation", "")


def aggregate(task_name, results):
    """Failed items count against the run: no schema credit, zero field accuracy, and the lowest rubric score.
    Latency covers items whose model call succeeded."""
    latencies = [r["latency_seconds"] for r in results if r.get("latency_seconds") is not None]
    values = {
        "schema_validity": sum(r["schema_valid"] for r in results) / len(results),
        "latency_p95_seconds": p95(latencies) if latencies else 0.0,
    }
    if task_name == "docs":
        scores = [score for r in results for score in r["field_scores"].values()]
        values["field_accuracy"] = sum(scores) / len(scores)
    elif task_name == "support":
        values["rubric_mean"] = sum(r["rubric_score"] for r in results) / len(results)
    return values


def apply_thresholds(values, thresholds):
    metrics = []
    for name, threshold in thresholds.items():
        value = values[name]
        if threshold["comparison"] == "min":
            passed = value >= threshold["value"]
        elif threshold["comparison"] == "max":
            passed = value <= threshold["value"]
        else:
            raise ValueError(f"unknown comparison {threshold['comparison']}")
        metrics.append(
            {
                "name": name,
                "definition": threshold["definition"],
                "value": float(value),
                "threshold": float(threshold["value"]),
                "comparison": threshold["comparison"],
                "passed": passed,
            }
        )
    return metrics
