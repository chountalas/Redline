from __future__ import annotations

from pathlib import Path

import pytest

from redline.focus import FOCUS_SCHEMA_NAME, _focus_schema, run_focus_pass
from redline.models import LeaseFacts
from redline.pdf_text import PDFText, TextPage
from tests.helpers import FakeOpenAIClient, synthetic_pembina_facts, text_response


def test_focus_pass_uses_structured_output(monkeypatch: pytest.MonkeyPatch) -> None:
    facts = LeaseFacts.model_validate(synthetic_pembina_facts("synthetic.pdf"))
    pdf_text = PDFText(
        path=Path("synthetic.pdf"),
        pages=[TextPage(page_number=1, text="Lease text")],
    )
    fake_client = FakeOpenAIClient(
        [
            text_response(
                {
                    "advisory_findings": [
                        {
                            "rule_id": "ADVISORY_focus",
                            "severity": "WARN",
                            "title": "Check negotiated economics",
                            "detail": "The advisory pass sees a possible deal-intent issue.",
                            "evidence": [{"quote": "Rent shall be $400,000", "page": 1}],
                            "expected": None,
                            "actual": None,
                        }
                    ]
                }
            )
        ]
    )
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: fake_client,
    )

    findings = run_focus_pass(
        facts,
        pdf_text,
        "Check negotiated rent.",
        provider="openai",
        model="openai-test-model",
    )

    call = fake_client.responses.calls[0]
    assert call["text"]["format"]["name"] == FOCUS_SCHEMA_NAME
    assert call["text"]["format"]["strict"] is True
    assert findings[0].severity == "ADVISORY"


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


def test_focus_schema_refs_resolve() -> None:
    schema = _focus_schema()
    defs = schema.get("$defs", {})
    refs: set[str] = set()
    _all_refs(schema, refs)
    for ref in refs:
        assert ref.startswith("#/$defs/"), f"unexpected ref form: {ref}"
        assert ref.split("/")[-1] in defs, f"dangling $ref: {ref}"
    assert refs, "expected at least one $ref (nested models present)"
