import pytest

from harness.models import response_text, validate_endpoint_url

PROJECTS = {"jd-aip-sandbox", "123456"}
PATH = "/v1/projects/123456/locations/us-east4/endpoints/987/chat/completions"


@pytest.mark.parametrize(
    "url",
    [
        f"https://us-east4-aiplatform.googleapis.com{PATH}",
        f"https://987.us-east4-123456.prediction.vertexai.goog{PATH}",
        "https://us-east4-aiplatform.googleapis.com/v1beta1/projects/jd-aip-sandbox/locations/us-east4/endpoints/987/chat/completions",
    ],
)
def test_accepts_prediction_hosts_for_the_evaluation_project(url):
    validate_endpoint_url(url, "us-east4", PROJECTS)


@pytest.mark.parametrize(
    "url",
    [
        f"http://us-east4-aiplatform.googleapis.com{PATH}",
        f"https://attacker.example{PATH}",
        f"https://us-east4-aiplatform.googleapis.com.attacker.example{PATH}",
        f"https://987.us-east4-999999.prediction.vertexai.goog{PATH}",
        "https://us-east4-aiplatform.googleapis.com/v1/projects/other/locations/us-east4/endpoints/987/chat/completions",
        "https://us-east4-aiplatform.googleapis.com/v1/projects/123456/locations/us-central1/endpoints/987/chat/completions",
    ],
)
def test_rejects_urls_that_could_receive_credentials_elsewhere(url):
    with pytest.raises(ValueError):
        validate_endpoint_url(url, "us-east4", PROJECTS)


def test_response_text_skips_thoughts_and_keeps_the_finish_reason():
    data = {"candidates": [{"content": {"parts": [{"text": "x", "thought": True}, {"text": "{}"}]}, "finishReason": "STOP"}]}
    assert response_text(data) == ("{}", "STOP")
    assert response_text({"promptFeedback": {"blockReason": "SAFETY"}}) == ("", "SAFETY")
