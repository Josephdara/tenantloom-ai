from urllib.parse import urlparse

from .api import api_host, post_json


def validate_endpoint_url(url, location, projects):
    """Rejects URLs outside Agent Platform prediction hosts for the given projects, because the harness sends its
    credentials to this URL."""
    parsed = urlparse(url)
    host = parsed.hostname or ""
    if parsed.scheme != "https":
        raise ValueError("endpoint URL must use https")
    labels = host.split(".")
    regional = host == f"{location}-aiplatform.googleapis.com"
    dedicated = host.endswith(".prediction.vertexai.goog") and len(labels) > 1 and any(
        labels[1] == f"{location}-{project}" for project in projects if project.isdigit()
    )
    if not (regional or dedicated):
        raise ValueError(f"endpoint host {host} is not an Agent Platform prediction host for these projects")
    segments = parsed.path.split("/")
    try:
        named = segments[segments.index("projects") + 1]
    except (ValueError, IndexError):
        named = None
    if named not in projects:
        raise ValueError("endpoint URL names a project other than the evaluation project")
    if f"/locations/{location}/endpoints/" not in parsed.path:
        raise ValueError(f"endpoint URL is not an endpoint in {location}")


def response_text(data):
    candidates = data.get("candidates") or []
    if not candidates:
        return "", data.get("promptFeedback", {}).get("blockReason")
    candidate = candidates[0]
    parts = candidate.get("content", {}).get("parts", [])
    text = "".join(part.get("text", "") for part in parts if not part.get("thought"))
    return text, candidate.get("finishReason")


def generate(sess, project, spec, prompt):
    """Calls the model once. Latency is the duration of the successful attempt, excluding retry waits."""
    stats = {}
    if spec["pattern"] == "self-deployed":
        body = {"messages": [{"role": "user", "content": prompt}], **spec["params"]}
        choice = post_json(sess, spec["endpoint_url"], body, stats=stats)["choices"][0]
        text, finish_reason = choice["message"].get("content") or "", choice.get("finish_reason")
    else:
        location = spec["location"]
        url = (
            f"{api_host(location)}/v1/projects/{project}/locations/{location}"
            f"/publishers/google/models/{spec['model_id']}:generateContent"
        )
        body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}], "generationConfig": spec["params"]}
        text, finish_reason = response_text(post_json(sess, url, body, stats=stats))
    return {"text": text, "finish_reason": finish_reason, "seconds": stats["seconds"], "attempts": stats["attempts"]}
