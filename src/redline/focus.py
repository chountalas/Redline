from __future__ import annotations

import json
from typing import Any

from pydantic import ValidationError

from redline.errors import ExtractionError
from redline.llm import LLMConfig, complete_structured, strict_object_schema
from redline.models import Finding, LeaseFacts, Severity
from redline.pdf_text import PDFText

SYSTEM_PROMPT = """You provide advisory commercial lease review findings for a narrow user focus.
Return only structured JSON matching the requested schema. Findings must be tagged ADVISORY and
must include source quote/page where possible. Do not override deterministic findings."""

FOCUS_SCHEMA_NAME = "advisory_findings"


def run_focus_pass(
    facts: LeaseFacts,
    pdf_text: PDFText,
    context: str,
    *,
    provider: str | None = None,
    model: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> list[Finding]:
    if not context.strip():
        return []
    config = LLMConfig.from_options(
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    raw = complete_structured(
        config=config,
        system=SYSTEM_PROMPT,
        prompt=_build_focus_prompt(facts, pdf_text, context),
        schema_name=FOCUS_SCHEMA_NAME,
        schema=_focus_schema(),
        max_output_tokens=2500,
    )
    findings = raw.get("advisory_findings", [])
    if not isinstance(findings, list):
        raise ExtractionError("Advisory response must contain advisory_findings list.")
    parsed: list[Finding] = []
    for item in findings:
        try:
            finding = Finding.model_validate(item)
        except ValidationError as exc:
            raise ExtractionError(f"Invalid advisory finding: {exc}") from exc
        parsed.append(finding.model_copy(update={"severity": Severity.ADVISORY}))
    return parsed


def _focus_schema() -> dict[str, Any]:
    finding = Finding.model_json_schema()
    defs: dict[str, Any] = {}
    defs.update(finding.pop("$defs", {}))
    schema: dict[str, Any] = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "advisory_findings": {
                "type": "array",
                "items": finding,
            }
        },
        "required": ["advisory_findings"],
    }
    if defs:
        schema["$defs"] = defs
    return strict_object_schema(schema)


def _build_focus_prompt(facts: LeaseFacts, pdf_text: PDFText, context: str) -> str:
    facts_json = json.dumps(facts.model_dump(mode="json"), indent=2)
    return f"""
Focus:
{context}

Extracted facts:
{facts_json}

Return zero or more advisory findings.

Lease text:
{pdf_text.as_prompt_text()}
""".strip()
