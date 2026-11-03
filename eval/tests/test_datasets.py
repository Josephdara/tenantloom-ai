import json

import pytest

from harness.config import load_task
from harness.datasets import dataset_uri, parse_items, sha256_bytes


def jsonl(*items):
    return "\n".join(json.dumps(item) for item in items).encode()


DOC_LABELS = {
    "invoice_number": "INV-1",
    "vendor_name": "Acme",
    "invoice_date": "2024-01-31",
    "currency": "USD",
    "total_amount": "10.00",
}


def test_dataset_uri_layout():
    assert dataset_uri("b", "docs", "v1") == "gs://b/datasets/docs/v1/items.jsonl"


def test_parse_items_accepts_a_valid_docs_file():
    items = parse_items(jsonl({"id": "d1", "document": "text", "labels": DOC_LABELS}), load_task("docs"))
    assert [item["id"] for item in items] == ["d1"]


@pytest.mark.parametrize(
    "item",
    [
        {"id": "d1", "labels": DOC_LABELS},
        {"id": "d1", "document": "text", "labels": {"invoice_number": "INV-1"}},
        {"id": "d1", "document": {"text": "nested"}, "labels": DOC_LABELS},
    ],
)
def test_parse_items_rejects_incomplete_items(item):
    with pytest.raises(ValueError):
        parse_items(jsonl(item), load_task("docs"))


def test_parse_items_rejects_duplicate_ids():
    item = {"id": "s1", "ticket": "text", "reference": "summary"}
    with pytest.raises(ValueError):
        parse_items(jsonl(item, item), load_task("support"))


def test_dataset_hash_changes_with_content():
    assert sha256_bytes(b"a") == sha256_bytes(b"a")
    assert sha256_bytes(b"a") != sha256_bytes(b"b")
