import hashlib
import json

from . import EVAL_ROOT


def load_json(relative_path):
    return json.loads((EVAL_ROOT / relative_path).read_text())


def read_text(relative_path):
    return (EVAL_ROOT / relative_path).read_text()


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_task(name):
    tasks = load_json("config/tasks.json")
    if name not in tasks:
        raise ValueError(f"unknown task {name}; expected one of {sorted(tasks)}")
    return tasks[name]


def load_model(model_id, endpoint_url=None):
    models = load_json("config/models.json")
    if model_id not in models:
        raise ValueError(f"unknown model {model_id}; expected one of {sorted(models)}")
    spec = dict(models[model_id], model_id=model_id, endpoint_url=endpoint_url)
    if spec["pattern"] == "self-deployed" and not endpoint_url:
        raise ValueError(f"{model_id} is self-deployed; pass --endpoint-url")
    return spec
