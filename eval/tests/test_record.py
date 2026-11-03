from datetime import datetime, timedelta, timezone

from fakes import FakeResponse, FakeSession
from harness import expire as expire_module
from harness.config import load_json, load_model, load_task
from harness.expire import expire, expired_deployments
from harness.record import build_record, run_name

PASSING = {"name": "m", "definition": "d", "value": 1.0, "threshold": 1.0, "comparison": "min", "passed": True}


def schema_fields(schema):
    return {field["name"]: field for field in schema}


def sample_record(task_name, item_limit=None, metrics=(PASSING,)):
    return build_record(
        run_id="r1",
        run_time=datetime(2024, 1, 1, tzinfo=timezone.utc),
        task_name=task_name,
        task=load_task(task_name),
        split="development",
        dataset_version="v1",
        dataset_sha256="abc",
        dataset_item_count=10,
        item_count=10 if item_limit is None else item_limit,
        item_limit=item_limit,
        item_errors=0,
        spec=load_model("gemini-3.8-flash"),
        prompt_sha256="def",
        rubric_sha256=None,
        evaluation_location="us-east4",
        metrics=list(metrics),
        image_digest=None,
        harness_version="0.1.0",
        harness_commit=None,
        report_uri=None,
        experiment_run=None,
    )


def test_record_matches_the_eval_runs_table_schema():
    fields = schema_fields(load_json("schema/eval_runs.json"))
    metric_fields = schema_fields(fields["metrics"]["fields"])
    for task_name in ("docs", "support"):
        record = sample_record(task_name)
        assert set(record) == set(fields)
        for name, field in fields.items():
            if field["mode"] == "REQUIRED":
                assert record[name] is not None, name
        for metric in record["metrics"]:
            assert set(metric) == set(metric_fields)


def test_a_limited_run_never_passes():
    assert sample_record("docs")["passed"]
    limited = sample_record("docs", item_limit=5)
    assert not limited["passed"]
    assert (limited["item_count"], limited["dataset_item_count"]) == (5, 10)


def test_a_failed_metric_fails_the_run():
    assert not sample_record("docs", metrics=[dict(PASSING, passed=False)])["passed"]


def test_judge_fields_are_recorded_only_for_judged_tasks():
    assert sample_record("support")["judge_model"] == "gemini-3.8-flash"
    assert sample_record("docs")["judge_model"] is None


def test_run_names_are_unique_per_run_and_short():
    first = run_name("docs", "heldout", "gemma-4-26b-a4b-it-maas", "a" * 32)
    second = run_name("docs", "heldout", "gemma-4-26b-a4b-it-maas", "b" * 32)
    assert first != second
    assert first == "docs-heldout-gemma-4-26b-a4b-it-maas-aaaaaaaa"
    assert len(run_name("docs", "heldout", "m" * 300, "a" * 32)) <= 100


def test_only_old_deployments_expire():
    now = datetime(2024, 1, 1, 12, tzinfo=timezone.utc)
    endpoints = [
        {
            "name": "projects/p/locations/l/endpoints/1",
            "deployedModels": [
                {"id": "old", "createTime": (now - timedelta(hours=5)).isoformat().replace("+00:00", "Z")},
                {"id": "new", "createTime": (now - timedelta(minutes=30)).isoformat().replace("+00:00", "Z")},
            ],
        },
        {"name": "projects/p/locations/l/endpoints/2"},
    ]
    assert expired_deployments(endpoints, now, timedelta(hours=4)) == [("projects/p/locations/l/endpoints/1", "old")]


def test_expiry_continues_past_a_failed_undeploy(monkeypatch):
    monkeypatch.setattr(expire_module, "list_endpoints", lambda *args: [])
    monkeypatch.setattr(
        expire_module,
        "expired_deployments",
        lambda *args: [("projects/p/locations/l/endpoints/1", "a"), ("projects/p/locations/l/endpoints/2", "b")],
    )
    sess = FakeSession(FakeResponse(400, {"error": "traffic"}), FakeResponse(200, {}))
    expired, failed = expire(sess, "p", "us-east4", 4, dry_run=False)
    assert len(expired) == 2
    assert failed == [("projects/p/locations/l/endpoints/1", "a")]
    assert len(sess.calls) == 2
