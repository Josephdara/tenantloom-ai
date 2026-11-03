import hashlib
import json


def dataset_uri(bucket, task, version):
    return f"gs://{bucket}/datasets/{task}/{version}/items.jsonl"


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def parse_items(data, task):
    required = ("id", task["input_field"], task["label_field"])
    items = []
    seen = set()
    for number, line in enumerate(data.decode("utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        item = json.loads(line)
        missing = [key for key in required if key not in item]
        if missing:
            raise ValueError(f"line {number} is missing {missing}")
        if not isinstance(item[task["input_field"]], str):
            raise ValueError(f"line {number} {task['input_field']} is not a string")
        if item["id"] in seen:
            raise ValueError(f"line {number} repeats id {item['id']}")
        if "fields" in task and set(item[task["label_field"]]) != set(task["fields"]):
            raise ValueError(f"line {number} labels do not match the task fields")
        seen.add(item["id"])
        items.append(item)
    if not items:
        raise ValueError("dataset has no items")
    return items


def read_gcs(uri):
    from google.cloud import storage

    bucket, _, name = uri.removeprefix("gs://").partition("/")
    return storage.Client().bucket(bucket).blob(name).download_as_bytes()
