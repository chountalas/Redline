from __future__ import annotations

from pathlib import Path

import pytest

from redline.errors import ExtractionError, ScannedPdfError
from redline.extractor import EXTRACTION_SCHEMA_NAME, extract_facts_from_text
from redline.pdf_text import PDFText, TextPage, extract_pdf_text
from tests.helpers import FakeOpenAIClient, synthetic_pembina_facts, text_response, write_pdf


def test_extract_facts_uses_openai_structured_output(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pdf_text = PDFText(
        path=Path("synthetic.pdf"),
        pages=[TextPage(page_number=1, text="Rent shall be $400,000 per Display Face.")],
    )
    fake_client = FakeOpenAIClient(
        [text_response(synthetic_pembina_facts("synthetic.pdf"))]
    )
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: fake_client,
    )

    facts = extract_facts_from_text(pdf_text, provider="openai", model="openai-test-model")

    call = fake_client.responses.calls[0]
    assert call["model"] == "openai-test-model"
    assert call["text"]["format"]["name"] == EXTRACTION_SCHEMA_NAME
    assert call["text"]["format"]["strict"] is True
    assert facts.per_face_rent.value is not None
    assert facts.per_face_rent.value.amount == 400000


def test_extract_facts_retries_once_on_invalid_tool_input(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pdf_text = PDFText(
        path=Path("synthetic.pdf"),
        pages=[TextPage(page_number=1, text="Rent shall be $400,000 per Display Face.")],
    )
    fake_client = FakeOpenAIClient(
        [
            text_response({"source_file": "synthetic.pdf", "page_count": "not-an-int"}),
            text_response(synthetic_pembina_facts("synthetic.pdf")),
        ]
    )
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: fake_client,
    )

    facts = extract_facts_from_text(pdf_text, provider="openai", model="openai-test-model")

    assert facts.page_count == 1
    assert len(fake_client.responses.calls) == 2
    assert "prior response was invalid" in fake_client.responses.calls[1]["input"][1]["content"]


def test_extract_facts_fails_after_two_invalid_tool_inputs(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pdf_text = PDFText(
        path=Path("synthetic.pdf"),
        pages=[TextPage(page_number=1, text="Rent shall be $400,000 per Display Face.")],
    )
    fake_client = FakeOpenAIClient(
        [
            text_response({"source_file": "synthetic.pdf", "page_count": "not-an-int"}),
            text_response({"source_file": "synthetic.pdf", "page_count": "not-an-int"}),
        ]
    )
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: fake_client,
    )

    with pytest.raises(ExtractionError, match="invalid structured output twice"):
        extract_facts_from_text(pdf_text, provider="openai", model="openai-test-model")


def test_extract_pdf_text_reads_synthetic_pdf(tmp_path: Path) -> None:
    pdf_path = tmp_path / "lease.pdf"
    write_pdf(pdf_path, ["Rent shall be $400,000 per Display Face."])

    pdf_text = extract_pdf_text(pdf_path)

    assert pdf_text.page_count == 1
    assert "per Display Face" in pdf_text.as_prompt_text()


def test_extract_pdf_text_rejects_blank_scanned_like_pdf(tmp_path: Path) -> None:
    pdf_path = tmp_path / "blank.pdf"
    write_pdf(pdf_path, [])

    with pytest.raises(ScannedPdfError, match="looks scanned"):
        extract_pdf_text(pdf_path)
