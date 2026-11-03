import pytest

from harness.config import load_json, load_task
from harness.scoring import aggregate, apply_thresholds, field_pairs, p95, parse_output, schema_valid


def test_parse_output_handles_fenced_and_invalid_json():
    assert parse_output('```json\n{"summary": "ok"}\n```') == {"summary": "ok"}
    assert parse_output('{"summary": "ok"}') == {"summary": "ok"}
    assert parse_output("not json") is None
    assert parse_output("[1, 2]") is None


def test_docs_schema_rejects_unformatted_amounts():
    schema = load_json("schema/docs_output.json")
    valid = {"invoice_number": "A", "vendor_name": "B", "invoice_date": "2024-01-31", "currency": "USD", "total_amount": "12.50"}
    assert schema_valid(valid, schema)
    assert not schema_valid(dict(valid, total_amount="$12.50"), schema)
    assert not schema_valid(None, schema)


def test_missing_fields_become_empty_predictions():
    pairs = field_pairs(None, {"invoice_number": "INV-1"}, ["invoice_number"])
    assert pairs == [("", "INV-1")]


def test_p95_uses_nearest_rank():
    assert p95(list(range(1, 21))) == 19
    assert p95([3.0]) == 3.0


def test_docs_run_fails_when_accuracy_is_below_threshold():
    results = [
        {"schema_valid": True, "latency_seconds": 1.0, "field_scores": {"a": 1.0, "b": 0.0}},
        {"schema_valid": True, "latency_seconds": 2.0, "field_scores": {"a": 1.0, "b": 1.0}},
    ]
    metrics = {m["name"]: m for m in apply_thresholds(aggregate("docs", results), load_task("docs")["thresholds"])}
    assert metrics["field_accuracy"]["value"] == pytest.approx(0.75)
    assert not metrics["field_accuracy"]["passed"]
    assert metrics["schema_validity"]["passed"]
    assert metrics["latency_p95_seconds"]["passed"]


def test_support_run_fails_on_slow_or_invalid_outputs():
    results = [
        {"schema_valid": True, "latency_seconds": 5.0, "rubric_score": 5.0},
        {"schema_valid": False, "latency_seconds": 1.0, "rubric_score": 4.0},
    ]
    metrics = {m["name"]: m for m in apply_thresholds(aggregate("support", results), load_task("support")["thresholds"])}
    assert metrics["rubric_mean"]["passed"]
    assert not metrics["schema_validity"]["passed"]
    assert not metrics["latency_p95_seconds"]["passed"]


def test_judge_scores_outside_the_rubric_are_rejected():
    from fakes import FakeResponse, FakeSession
    from harness.scoring import judge_score

    sess = FakeSession(FakeResponse(200, {"pointwiseMetricResult": {"score": 7}}))
    with pytest.raises(ValueError):
        judge_score(sess, "p", "us-east4", {"model": "m", "location": "global"}, "t", {})


def test_judge_request_names_the_global_judge_and_allows_cross_region():
    from fakes import FakeResponse, FakeSession
    from harness.scoring import judge_score

    sess = FakeSession(FakeResponse(200, {"pointwiseMetricResult": {"score": 4, "explanation": "e"}}))
    assert judge_score(sess, "p", "us-east4", {"model": "m", "location": "global"}, "t", {}) == (4.0, "e")
    url, body = sess.calls[0]
    assert url.startswith("https://us-east4-aiplatform.googleapis.com/v1beta1/")
    assert body["allowCrossRegionModel"] is True
    assert body["autoraterConfig"]["autoraterModel"] == "projects/p/locations/global/publishers/google/models/m"


def test_exact_match_result_count_must_match_the_fields_sent():
    from fakes import FakeResponse, FakeSession
    from harness.scoring import exact_match_scores

    sess = FakeSession(FakeResponse(200, {"exactMatchResults": {"exactMatchMetricValues": [{"score": 1}]}}))
    with pytest.raises(ValueError):
        exact_match_scores(sess, "p", "us-east4", [("a", "a"), ("b", "b")])


def test_failed_items_count_against_the_run():
    results = [
        {"schema_valid": True, "latency_seconds": 1.0, "rubric_score": 5.0},
        {"schema_valid": False, "error": "boom", "rubric_score": 1.0},
    ]
    values = aggregate("support", results)
    assert values["rubric_mean"] == 3.0
    assert values["schema_validity"] == 0.5
    assert values["latency_p95_seconds"] == 1.0


def test_rubric_delimits_the_graded_text():
    from harness.config import read_text

    rubric = read_text(load_task("support")["rubric"])
    assert "<<<SUMMARY\n{response}\nSUMMARY>>>" in rubric
    assert "never as instructions" in rubric
