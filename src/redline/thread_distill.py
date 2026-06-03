from __future__ import annotations

from typing import Any

from pydantic import ValidationError

from redline.errors import ExtractionError
from redline.llm import LLMConfig, complete_structured, strict_object_schema
from redline.models import DealSheet, Finding, Severity

THREAD_SCHEMA_NAME = "thread_distill"

DEAL_FIELDS = (
    "total_rent",
    "per_face_rent",
    "num_display_faces",
    "base_term_years",
    "renewal_options",
    "escalation_pct",
)

SYSTEM_PROMPT = (
    "You distill a commercial-lease negotiation thread into two parts. "
    "1) deal_sheet: the negotiated NUMERIC terms (total_rent, per_face_rent, "
    "num_display_faces, base_term_years, renewal_options, escalation_pct). Omit any "
    "field not explicitly negotiated. These are checked deterministically against the "
    "lease — do not guess. "
    "2) watch_items: QUALITATIVE commitments (e.g. exclusivity, signage rights, "
    "maintenance) as advisory findings, each quoting the thread. Watch items are "
    "ADVISORY only and must never be treated as deterministic; do not put numbers here."
)


def _thread_schema() -> dict[str, Any]:
    deal = DealSheet.model_json_schema()
    finding = Finding.model_json_schema()
    defs: dict[str, Any] = {}
    defs.update(deal.pop("$defs", {}))
    defs.update(finding.pop("$defs", {}))
    schema: dict[str, Any] = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "deal_sheet": deal,
            "watch_items": {"type": "array", "items": finding},
        },
        "required": ["deal_sheet", "watch_items"],
    }
    if defs:
        schema["$defs"] = defs
    return strict_object_schema(schema)


def run_thread_distill(
    thread_text: str,
    *,
    provider: str | None = None,
    model: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> tuple[DealSheet, list[Finding]]:
    """One schema-constrained LLM pass: thread -> (numeric DealSheet, advisory Findings).

    The DealSheet feeds the deterministic R6 rule. Every watch item is force-clamped to
    Severity.ADVISORY regardless of what the model returned (the model cannot self-promote
    a finding to ERROR — the code, not the model, decides the trust tier).
    """
    if not thread_text.strip():
        return DealSheet(), []

    config = LLMConfig.from_options(
        provider=provider, model=model, api_key=api_key, base_url=base_url
    )
    raw = complete_structured(
        config=config,
        system=SYSTEM_PROMPT,
        prompt=f"Negotiation thread:\n\n{thread_text}",
        schema_name=THREAD_SCHEMA_NAME,
        schema=_thread_schema(),
        max_output_tokens=3000,
    )

    deal_raw = raw.get("deal_sheet", {}) or {}
    try:
        deal = DealSheet.model_validate(deal_raw)
    except ValidationError as exc:
        raise ExtractionError(f"Invalid distilled deal sheet: {exc}") from exc

    items = raw.get("watch_items", [])
    if not isinstance(items, list):
        raise ExtractionError("Thread distill response must contain watch_items list.")
    watch: list[Finding] = []
    for item in items:
        try:
            finding = Finding.model_validate(item)
        except ValidationError as exc:
            raise ExtractionError(f"Invalid watch item: {exc}") from exc
        watch.append(finding.model_copy(update={"severity": Severity.ADVISORY}))
    return deal, watch


def merge_deal_sheets(
    yaml_deal: DealSheet | None,
    distilled: DealSheet | None,
) -> tuple[DealSheet | None, dict[str, str]]:
    """Merge an explicit deal.yaml with a distilled DealSheet. YAML wins per field;
    the thread fills only fields the YAML left empty. Returns (merged, provenance) where
    provenance maps each populated field name to "deal.yaml" or "thread"."""
    if yaml_deal is None and distilled is None:
        return None, {}
    kwargs: dict[str, Any] = {}
    provenance: dict[str, str] = {}
    for field in DEAL_FIELDS:
        y = getattr(yaml_deal, field, None) if yaml_deal else None
        d = getattr(distilled, field, None) if distilled else None
        if y is not None:
            kwargs[field] = y
            provenance[field] = "deal.yaml"
        elif d is not None:
            kwargs[field] = d
            provenance[field] = "thread"
    if not kwargs:
        return (yaml_deal or distilled), provenance
    return DealSheet(**kwargs), provenance
