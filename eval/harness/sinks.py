import json

EXPERIMENT = "catalog-eval"


def write_report(project, bucket, run_id, report):
    from google.cloud import storage

    name = f"reports/{run_id}.json"
    storage.Client(project=project).bucket(bucket).blob(name).upload_from_string(
        json.dumps(report, indent=2), content_type="application/json"
    )
    return f"gs://{bucket}/{name}"


def log_experiment(project, location, name, params, metrics):
    from google.cloud import aiplatform

    # Without this, the SDK creates a default TensorBoard instance on first use.
    aiplatform.init(project=project, location=location, experiment=EXPERIMENT, experiment_tensorboard=False)
    aiplatform.start_run(name)
    aiplatform.log_params(params)
    aiplatform.log_metrics(metrics)
    aiplatform.end_run()
    return f"{EXPERIMENT}/{name}"


def insert_record(project, table, record):
    from google.cloud import bigquery

    errors = bigquery.Client(project=project).insert_rows_json(table, [record], row_ids=[record["run_id"]])
    if errors:
        raise RuntimeError(f"failed to insert the evaluation record: {errors}")
