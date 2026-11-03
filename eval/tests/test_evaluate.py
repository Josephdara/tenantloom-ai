import json

import pytest

import harness.__main__ as cli

DOC_LABELS = {
    "invoice_number": "INV-1",
    "vendor_name": "Acme",
    "invoice_date": "2024-01-31",
    "currency": "USD",
    "total_amount": "10.00",
}


@pytest.fixture
def sinks(monkeypatch):
    """Replaces every cloud call; returns what the run wrote."""
    written = {}
    items = [{"id": f"d{n}", "document": f"doc {n}", "labels": DOC_LABELS} for n in range(3)]
    monkeypatch.setattr(cli, "read_gcs", lambda uri: "\n".join(json.dumps(i) for i in items).encode())
    monkeypatch.setattr(cli, "session", lambda: object())

    def generate(sess, project, spec, prompt):
        if "doc 1" in prompt:
            raise RuntimeError("model unavailable")
        return {"text": json.dumps(DOC_LABELS), "finish_reason": "STOP", "seconds": 1.0, "attempts": 1}

    monkeypatch.setattr(cli, "generate", generate)
    monkeypatch.setattr(cli, "exact_match_scores", lambda sess, project, location, pairs: [1.0] * len(pairs))
    monkeypatch.setattr(cli, "write_report", lambda project, bucket, run_id, report: written.update(bucket=bucket, report=report) or f"gs://{bucket}/r")

    def broken_experiments(*args):
        raise RuntimeError("experiments down")

    monkeypatch.setattr(cli, "log_experiment", broken_experiments)
    monkeypatch.setattr(cli, "insert_record", lambda project, table, record: written.update(record=record))
    return written


def run(*extra):
    return cli.main(
        ["--project", "p", "run", "--task", "docs", "--dataset-version", "v1", "--model", "gemini-3.8-flash",
         "--dev-bucket", "p-eval-dev", "--heldout-bucket", "q-eval-heldout", *extra]
    )


def test_held_out_reports_stay_in_the_held_out_bucket(sinks):
    run("--split", "heldout")
    assert sinks["bucket"] == "q-eval-heldout"
    run("--split", "development")
    assert sinks["bucket"] == "p-eval-dev"


def test_a_failed_item_is_recorded_without_ending_the_run(sinks):
    run("--split", "development")
    record = sinks["record"]
    assert record["item_errors"] == 1
    assert record["item_count"] == 3
    assert not record["passed"]
    assert record["experiment_run"] is None
    failed = [item for item in sinks["report"]["items"] if "error" in item]
    assert failed[0]["id"] == "d1"


def test_limit_is_recorded_and_must_be_positive(sinks):
    run("--split", "development", "--limit", "1")
    assert (sinks["record"]["item_limit"], sinks["record"]["dataset_item_count"]) == (1, 3)
    with pytest.raises(SystemExit):
        run("--split", "development", "--limit", "0")


def test_self_deployed_models_reject_foreign_endpoint_urls(sinks):
    with pytest.raises(ValueError):
        cli.main(
            ["--project", "p", "run", "--task", "docs", "--split", "development", "--dataset-version", "v1",
             "--model", "gemma3n", "--dev-bucket", "p-eval-dev", "--endpoint-url", "https://attacker.example/v1/projects/p"]
        )
