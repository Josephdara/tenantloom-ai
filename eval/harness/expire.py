import sys
from datetime import datetime, timedelta, timezone

from .api import api_host, post_json


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def expired_deployments(endpoints, now, max_age):
    """Returns (endpoint name, deployed model ID) for every deployment older than max_age."""
    expired = []
    for endpoint in endpoints:
        for deployed in endpoint.get("deployedModels", []):
            if now - parse_time(deployed["createTime"]) > max_age:
                expired.append((endpoint["name"], deployed["id"]))
    return expired


def list_endpoints(sess, project, location):
    url = f"{api_host(location)}/v1/projects/{project}/locations/{location}/endpoints"
    endpoints, token = [], None
    while True:
        response = sess.get(url, params={"pageToken": token} if token else None, timeout=60)
        response.raise_for_status()
        data = response.json()
        endpoints.extend(data.get("endpoints", []))
        token = data.get("nextPageToken")
        if not token:
            return endpoints


def expire(sess, project, location, max_age_hours, dry_run):
    """Undeploys each expired deployment, continuing past failures. Returns the expired and failed deployments."""
    now = datetime.now(timezone.utc)
    expired = expired_deployments(list_endpoints(sess, project, location), now, timedelta(hours=max_age_hours))
    failed = []
    for endpoint, deployed_model_id in expired:
        print(f"{'would undeploy' if dry_run else 'undeploying'} {deployed_model_id} from {endpoint}")
        if dry_run:
            continue
        try:
            post_json(sess, f"{api_host(location)}/v1/{endpoint}:undeployModel", {"deployedModelId": deployed_model_id})
        except Exception as error:
            print(f"failed to undeploy {deployed_model_id} from {endpoint}: {error}", file=sys.stderr)
            failed.append((endpoint, deployed_model_id))
    return expired, failed
