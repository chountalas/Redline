from __future__ import annotations

from pathlib import Path

from pydantic import ValidationError

from redline.errors import ExtractionError
from redline.llm import LLMConfig, complete_structured, strict_model_schema
from redline.models import LeaseFacts
from redline.pdf_text import PDFText, extract_pdf_text

SYSTEM_PROMPT = """You extract commercial lease facts for deterministic validation.
Return only structured JSON matching the requested schema. Do not make legal judgments.
Every extracted value should carry the source quote and 1-based page number when available.
Use null when unsure."""

EXTRACTION_SCHEMA_NAME = "lease_facts"


def extract_facts_from_pdf(
    path: str | Path,
    *,
    provider: str | None = None,
    model: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> LeaseFacts:
    pdf_text = extract_pdf_text(path)
    return extract_facts_from_text(
        pdf_text,
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )


def extract_facts_from_text(
    pdf_text: PDFText,
    *,
    provider: str | None = None,
    model: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> LeaseFacts:
    config = LLMConfig.from_options(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    prompt = _build_extraction_prompt(pdf_text)
    last_error: Exception | None = None

    for attempt in range(2):
        raw = complete_structured(
            config=config,
            system=SYSTEM_PROMPT,
            prompt=prompt,
            schema_name=EXTRACTION_SCHEMA_NAME,
            schema=strict_model_schema(LeaseFacts),
            max_output_tokens=5000,
        )
        try:
            return _facts_from_mapping(raw, pdf_text)
        except ExtractionError as exc:
            last_error = exc
            prompt = (
                _build_extraction_prompt(pdf_text)
                + "\n\nYour prior response was invalid for this reason:\n"
                + str(exc)
                + "\nReturn corrected structured output."
            )
            if attempt == 1:
                break

    raise ExtractionError(
        f"Model extraction returned invalid structured output twice: {last_error}"
    )


def _build_extraction_prompt(pdf_text: PDFText) -> str:
    return f"""
Extract this commercial lease into the requested structured output schema.

Rules:
- Money should be objects like {{"amount": "400000", "currency": "CAD"}}.
- Dates must be ISO YYYY-MM-DD.
- rent_basis must be "per_face", "total", or "unknown".
- escalation_pct is the percent number, so two percent is 2, not 0.02.
- renewal_options is a list of year counts like [5, 5, 5].
- amount_word_pairs should include every numeral/spelled-out money pair you can find.
- Use null for uncertain values, but still include quote/page when they explain uncertainty.
- Use EXACTLY the field names shown below. rent_schedule items use keys
  label/amount/quote/page (not year/rent). amount_word_pairs items use keys
  numeral/words/quote/page (not value). Use [] for arrays when none apply.
- rent_schedule must list ONE entry per year of the base term (e.g. 15 entries for a
  15-year term), each amount being the rent payable for that single year, so the entries
  sum to stated_total_rent over the whole term. Expand any multi-year band (e.g.
  "$30,000 per annum for years 1-5") into one entry per year. When the lease quotes
  alternative rates for different display-face counts, use only the rate matching
  num_display_faces (do not include the other option as separate lines).

JSON shape (replace example item values with real data, or use [] if none):
{{
  "source_file": "{pdf_text.path}",
  "page_count": {pdf_text.page_count},
  "stated_total_rent": {{"value": null, "quote": null, "page": null}},
  "rent_basis": {{"value": "unknown", "quote": null, "page": null}},
  "per_face_rent": {{"value": null, "quote": null, "page": null}},
  "num_display_faces": {{"value": null, "quote": null, "page": null}},
  "rent_schedule": [
    {{
      "label": "Year 1",
      "amount": {{"amount": "200000", "currency": "CAD"}},
      "quote": null, "page": null
    }}
  ],
  "escalation_pct": {{"value": null, "quote": null, "page": null}},
  "escalation_clause_present": {{"value": null, "quote": null, "page": null}},
  "amount_word_pairs": [
    {{
      "numeral": {{"amount": "400000", "currency": "CAD"}},
      "words": "Four Hundred Thousand Dollars",
      "quote": null, "page": null
    }}
  ],
  "commencement_date": {{"value": null, "quote": null, "page": null}},
  "base_term_years": {{"value": null, "quote": null, "page": null}},
  "renewal_options": {{"value": null, "quote": null, "page": null}},
  "stated_expiry_date": {{"value": null, "quote": null, "page": null}},
  "extraction_notes": null
}}

Lease text:
{pdf_text.as_prompt_text()}
""".strip()


def _facts_from_mapping(raw: dict[str, object], pdf_text: PDFText) -> LeaseFacts:
    raw.setdefault("source_file", str(pdf_text.path))
    raw.setdefault("page_count", pdf_text.page_count)
    try:
        return LeaseFacts.model_validate(raw)
    except ValidationError as exc:
        raise ExtractionError(
            f"Extraction tool input did not match LeaseFacts schema: {exc}"
        ) from exc
