import json
import re


def run_name(task, split, model_id, run_id):
    # Experiments prefixes run resource IDs with the experiment name, so the name stays well under 128 characters.
    name = f"{task}-{split}-{model_id}-{run_id[:8]}".lower()
    return re.sub(r"[^a-z0-9-]", "-", name)[:100]


def build_record(
    *,
    run_id,
    run_time,
    task_name,
    task,
    split,
    dataset_version,
    dataset_sha256,
    dataset_item_count,
    item_count,
    item_limit,
    item_errors,
    spec,
    prompt_sha256,
    rubric_sha256,
    evaluation_location,
    metrics,
    image_digest,
    harness_version,
    harness_commit,
    report_uri,
    experiment_run,
):
    judge = task.get("judge")
    return {
        "run_id": run_id,
        "run_time": run_time.isoformat(),
        "task": task_name,
        "split": split,
        "dataset_version": dataset_version,
        "dataset_sha256": dataset_sha256,
        "dataset_item_count": dataset_item_count,
        "item_count": item_count,
        "item_limit": item_limit,
        "item_errors": item_errors,
        "model_id": spec["model_id"],
        "model_location": spec["location"],
        "deployment_pattern": spec["pattern"],
        "endpoint": spec.get("endpoint_url"),
        "prompt_version": task["prompt_version"],
        "prompt_sha256": prompt_sha256,
        "generation_params": json.dumps(spec["params"], sort_keys=True),
        "image_digest": image_digest,
        "harness_version": harness_version,
        "harness_commit": harness_commit,
        "evaluation_location": evaluation_location,
        "judge_model": judge["model"] if judge else None,
        "judge_location": judge["location"] if judge else None,
        "rubric_version": task.get("rubric_version"),
        "rubric_sha256": rubric_sha256,
        "metrics": metrics,
        # A run limited to part of the dataset is a smoke test and never counts as a pass.
        "passed": item_limit is None and all(metric["passed"] for metric in metrics),
        "report_uri": report_uri,
        "experiment_run": experiment_run,
    }
