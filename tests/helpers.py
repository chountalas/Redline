from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any


class FakeResponses:
    def __init__(self, responses: list[SimpleNamespace]) -> None:
        self._responses = iter(responses)
        self.calls: list[dict[str, Any]] = []

    def create(self, **kwargs: Any) -> SimpleNamespace:
        self.calls.append(kwargs)
        return next(self._responses)


class FakeOpenAIClient:
    def __init__(self, responses: list[SimpleNamespace]) -> None:
        self.responses = FakeResponses(responses)


class FakeMessages:
    def __init__(self, responses: list[SimpleNamespace]) -> None:
        self._responses = iter(responses)
        self.calls: list[dict[str, Any]] = []

    def create(self, **kwargs: Any) -> SimpleNamespace:
        self.calls.append(kwargs)
        return next(self._responses)


class FakeAnthropicClient:
    def __init__(self, responses: list[SimpleNamespace]) -> None:
        self.messages = FakeMessages(responses)


def text_response(output: dict[str, Any]) -> SimpleNamespace:
    return SimpleNamespace(output_text=json.dumps(output))


def tool_response(name: str, tool_input: dict[str, Any]) -> SimpleNamespace:
    return SimpleNamespace(
        content=[
            SimpleNamespace(
                type="tool_use",
                name=name,
                input=tool_input,
            )
        ]
    )


def write_pdf(path: Path, lines: list[str]) -> None:
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen import canvas

    pdf = canvas.Canvas(str(path), pagesize=letter)
    _, height = letter
    y = height - 72
    for line in lines:
        pdf.drawString(72, y, line)
        y -= 16
        if y < 72:
            pdf.showPage()
            y = height - 72
    pdf.save()


def synthetic_pembina_facts(source_file: str) -> dict[str, Any]:
    return {
        "source_file": source_file,
        "page_count": 1,
        "stated_total_rent": {
            "value": {"amount": "400000", "currency": "CAD"},
            "quote": "Total rent shall be $400,000.",
            "page": 1,
        },
        "rent_basis": {
            "value": "per_face",
            "quote": "Rent shall be $400,000 per Display Face.",
            "page": 1,
        },
        "per_face_rent": {
            "value": {"amount": "400000", "currency": "CAD"},
            "quote": "$400,000 per Display Face",
            "page": 1,
        },
        "num_display_faces": {
            "value": 2,
            "quote": "The Premises include two Display Faces.",
            "page": 1,
        },
        "rent_schedule": [
            {
                "label": "Year 1",
                "amount": {"amount": "200000", "currency": "CAD"},
                "quote": "Year 1: $200,000",
                "page": 1,
            },
            {
                "label": "Year 2",
                "amount": {"amount": "200000", "currency": "CAD"},
                "quote": "Year 2: $200,000",
                "page": 1,
            },
        ],
        "escalation_pct": {"value": None, "quote": None, "page": None},
        "escalation_clause_present": {
            "value": False,
            "quote": "No annual escalation applies.",
            "page": 1,
        },
        "amount_word_pairs": [
            {
                "numeral": {"amount": "400000", "currency": "CAD"},
                "words": "Four Hundred Thousand Dollars",
                "quote": "$400,000 (Four Hundred Thousand Dollars)",
                "page": 1,
            }
        ],
        "commencement_date": {
            "value": "2026-01-01",
            "quote": "commences January 1, 2026",
            "page": 1,
        },
        "base_term_years": {
            "value": "2",
            "quote": "two year term",
            "page": 1,
        },
        "renewal_options": {
            "value": [],
            "quote": "no renewal options",
            "page": 1,
        },
        "stated_expiry_date": {
            "value": "2027-12-31",
            "quote": "expires December 31, 2027",
            "page": 1,
        },
        "extraction_notes": "Synthetic fixture only.",
    }
