import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timezone

from . import __version__
from .api import session
from .config import load_json, load_model, load_task, read_text, sha256_text
from .datasets import dataset_uri, parse_items, read_gcs, sha256_bytes
from .expire import expire
from .models import generate, validate_endpoint_url
from .record import build_record, run_name
from .scoring import aggregate, apply_thresholds, exact_match_scores, field_pairs, judge_score, parse_output, schema_valid
from .sinks import insert_record, log_experiment, write_report


def score_item(sess, args, task, spec, prompt_template, rubric, output_schema, item):
    """Scores one item. A failure is recorded on the item instead of ending the run."""
    result = {"id": item["id"]}
    try:
        call = generate(sess, args.project, spec, prompt_template.replace("{" + task["input_field"] + "}", item[task["input_field"]]))
        result.update(
            latency_seconds=call["seconds"], attempts=call["attempts"], finish_reason=call["finish_reason"], output=call["text"]
        )
        output = parse_output(call["text"])
        result["schema_valid"] = schema_valid(output, output_schema)
        if args.task == "docs":
            pairs = field_pairs(output, item[task["label_field"]], task["fields"])
            result["field_scores"] = dict(zip(task["fields"], exact_match_scores(sess, args.project, args.evaluation_location, pairs)))
        else:
            response = output["summary"] if result["schema_valid"] else call["text"]
            instance = {"ticket": item[task["input_field"]], "reference": item[task["label_field"]], "response": response}
            result["rubric_score"], result["judge_explanation"] = judge_score(
                sess, args.project, args.evaluation_location, task["judge"], rubric, instance
            )
    except Exception as error:
        result["error"] = f"{type(error).__name__}: {error}"[:1000]
        result.setdefault("schema_valid", False)
        if args.task == "docs":
            result["field_scores"] = {field: 0.0 for field in task["fields"]}
        else:
            result["rubric_score"] = 1.0
    return result


def evaluate(args):
    task = load_task(args.task)
    spec = load_model(args.model, args.endpoint_url)
    if spec["endpoint_url"]:
        validate_endpoint_url(spec["endpoint_url"], spec["location"], {args.project, os.environ.get("PROJECT_NUMBER", "")})
    bucket = args.dev_bucket if args.split == "development" else args.heldout_bucket
    if not bucket:
        raise ValueError(f"no bucket configured for the {args.split} split")

    prompt_template = read_text(task["prompt"])
    if "{" + task["input_field"] + "}" not in prompt_template:
        raise ValueError(f"{task['prompt']} has no {{{task['input_field']}}} placeholder")
    rubric = read_text(task["rubric"]) if "rubric" in task else None
    output_schema = load_json(task["output_schema"])

    run_id = uuid.uuid4().hex
    run_time = datetime.now(timezone.utc)
    uri = dataset_uri(bucket, args.task, args.dataset_version)
    data = read_gcs(uri)
    all_items = parse_items(data, task)
    items = all_items[: args.limit] if args.limit else all_items

    sess = session()
    results = [score_item(sess, args, task, spec, prompt_template, rubric, output_schema, item) for item in items]
    item_errors = sum("error" in r for r in results)
    metrics = apply_thresholds(aggregate(args.task, results), task["thresholds"])

    # Reports carry model outputs and judge explanations, so they stay in the bucket of the split they came from.
    report_uri = write_report(
        args.project, bucket, run_id, {"run_id": run_id, "dataset_uri": uri, "metrics": metrics, "items": results}
    )
    name = run_name(args.task, args.split, spec["model_id"], run_id)
    experiment_run = None
    try:
        experiment_run = log_experiment(
            args.project,
            args.evaluation_location,
            name,
            {"task": args.task, "split": args.split, "dataset_version": args.dataset_version,
             "model_id": spec["model_id"], "prompt_version": task["prompt_version"], "run_id": run_id},
            {metric["name"]: metric["value"] for metric in metrics},
        )
    except Exception as error:
        print(f"Experiments logging failed; the record is still written: {error}", file=sys.stderr)

    record = build_record(
        run_id=run_id,
        run_time=run_time,
        task_name=args.task,
        task=task,
        split=args.split,
        dataset_version=args.dataset_version,
        dataset_sha256=sha256_bytes(data),
        dataset_item_count=len(all_items),
        item_count=len(items),
        item_limit=args.limit,
        item_errors=item_errors,
        spec=spec,
        prompt_sha256=sha256_text(prompt_template),
        rubric_sha256=sha256_text(rubric) if rubric else None,
        evaluation_location=args.evaluation_location,
        metrics=metrics,
        image_digest=os.environ.get("IMAGE_DIGEST"),
        harness_version=__version__,
        harness_commit=os.environ.get("HARNESS_COMMIT"),
        report_uri=report_uri,
        experiment_run=experiment_run,
    )
    insert_record(args.project, args.table, record)
    print(json.dumps({key: record[key] for key in ("run_id", "passed", "item_errors", "metrics", "report_uri")}, indent=2))
    return 0


def positive_int(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return number


def main(argv=None):
    parser = argparse.ArgumentParser(prog="harness")
    parser.add_argument("--project", default=os.environ.get("PROJECT_ID"))
    commands = parser.add_subparsers(dest="command", required=True)

    run = commands.add_parser("run", help="evaluate one model on one dataset split")
    run.add_argument("--task", required=True, choices=["docs", "support"])
    run.add_argument("--split", required=True, choices=["development", "heldout"])
    run.add_argument("--dataset-version", required=True)
    run.add_argument("--model", required=True)
    run.add_argument("--endpoint-url", help="chat completions URL of a self-deployed model's endpoint")
    run.add_argument("--dev-bucket", default=os.environ.get("EVAL_DEV_BUCKET"))
    run.add_argument("--heldout-bucket", default=os.environ.get("EVAL_HELDOUT_BUCKET"))
    run.add_argument("--evaluation-location", default=os.environ.get("EVAL_LOCATION", "us-east4"))
    run.add_argument("--table", default=os.environ.get("EVAL_RUNS_TABLE"))
    run.add_argument("--limit", type=positive_int, help="evaluate only the first N items; the run cannot pass")

    sweep = commands.add_parser("expire-endpoints", help="undeploy sandbox models older than a maximum age")
    sweep.add_argument("--location", default=os.environ.get("EVAL_LOCATION", "us-east4"))
    sweep.add_argument("--max-age-hours", type=float, default=float(os.environ.get("MAX_AGE_HOURS", "4")))
    sweep.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)
    if not args.project:
        parser.error("--project or PROJECT_ID is required")
    if args.command == "run":
        args.table = args.table or f"{args.project}.catalog_eval.eval_runs"
        return evaluate(args)
    _, failed = expire(session(), args.project, args.location, args.max_age_hours, args.dry_run)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
