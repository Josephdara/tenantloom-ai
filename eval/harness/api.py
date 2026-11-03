import time

import requests

RETRY_STATUS = {429, 500, 502, 503, 504}


class ApiError(RuntimeError):
    def __init__(self, status, body, url):
        super().__init__(f"HTTP {status} from {url}: {body}")
        self.status = status


def api_host(location):
    if location == "global":
        return "https://aiplatform.googleapis.com"
    if location in ("us", "eu"):
        return f"https://aiplatform.{location}.rep.googleapis.com"
    return f"https://{location}-aiplatform.googleapis.com"


def session():
    import google.auth
    from google.auth.transport.requests import AuthorizedSession

    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    return AuthorizedSession(credentials)


def post_json(sess, url, body, attempts=5, stats=None):
    """Posts JSON, retrying transport errors and transient statuses.

    If stats is a dict, it receives the number of attempts and the duration of the final attempt in seconds.
    """
    for attempt in range(1, attempts + 1):
        start = time.monotonic()
        try:
            response = sess.post(url, json=body, timeout=180)
        except (requests.ConnectionError, requests.Timeout):
            if attempt == attempts:
                raise
            time.sleep(2 ** (attempt - 1))
            continue
        elapsed = time.monotonic() - start
        if response.status_code in RETRY_STATUS and attempt < attempts:
            time.sleep(2 ** (attempt - 1))
            continue
        break
    if stats is not None:
        stats.update(attempts=attempt, seconds=elapsed)
    if response.status_code >= 400:
        raise ApiError(response.status_code, response.text[:2000], url)
    return response.json()
