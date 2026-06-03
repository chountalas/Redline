from __future__ import annotations

import pytest

from redline.models import DealSheet, Severity
from redline.thread_distill import _thread_schema, merge_deal_sheets, run_thread_distill
from tests.helpers import FakeOpenAIClient, text_response


def _seed(monkeypatch: pytest.MonkeyPatch, payload: dict) -> FakeOpenAIClient:
    fake = FakeOpenAIClient([text_response(payload)])
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: fake,
    )
    return fake


def test_distill_extracts_numeric_dealsheet_and_clamps_watch_items(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _seed(
        monkeypatch,
        {
            "deal_sheet": {"total_rent": "600000", "num_display_faces": 2},
            "watch_items": [
                {
                    "rule_id": "ADVISORY_thread",
                    "severity": "ERROR",
                    "title": "Category exclusivity promised",
                    "detail": "Thread says landlord grants billboard-category exclusivity.",
                    "evidence": [{"quote": "you'll be the only billboard", "page": None}],
                    "expected": None,
                    "actual": None,
                }
            ],
        },
    )

    deal, watch = run_thread_distill(
        "…negotiation thread…",
        provider="openai",
        model="openai-test-model",
    )

    assert isinstance(deal, DealSheet)
    assert deal.total_rent is not None and deal.num_display_faces == 2
    assert len(watch) == 1
    assert watch[0].severity == Severity.ADVISORY


def test_distill_empty_thread_is_a_noop(monkeypatch: pytest.MonkeyPatch) -> None:
    deal, watch = run_thread_distill("   ", provider="openai")
    assert deal == DealSheet()
    assert watch == []


def test_merge_yaml_wins_thread_fills_gaps() -> None:
    from decimal import Decimal

    from redline.models import Money

    yaml_deal = DealSheet(total_rent=Money(amount=Decimal("600000"), currency="CAD"))
    distilled = DealSheet(
        total_rent=Money(amount=Decimal("999999"), currency="CAD"),
        num_display_faces=2,
    )
    merged, provenance = merge_deal_sheets(yaml_deal, distilled)
    assert merged is not None
    assert merged.total_rent.amount == Decimal("600000")
    assert merged.num_display_faces == 2
    assert provenance["total_rent"] == "deal.yaml"
    assert provenance["num_display_faces"] == "thread"


def _all_refs(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "$ref" and isinstance(v, str):
                out.add(v)
            else:
                _all_refs(v, out)
    elif isinstance(node, list):
        for x in node:
            _all_refs(x, out)


def test_thread_schema_refs_resolve() -> None:
    schema = _thread_schema()
    defs = schema.get("$defs", {})
    refs: set[str] = set()
    _all_refs(schema, refs)
    for ref in refs:
        assert ref.startswith("#/$defs/"), f"unexpected ref form: {ref}"
        assert ref.split("/")[-1] in defs, f"dangling $ref: {ref}"
    assert refs, "expected at least one $ref (nested models present)"
