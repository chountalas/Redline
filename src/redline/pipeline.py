from __future__ import annotations

from pathlib import Path

from redline.deal import load_deal_sheet
from redline.errors import ExtractionError
from redline.extractor import extract_facts_from_text
from redline.focus import run_focus_pass
from redline.models import CheckReport, DealSheet, Finding, LeaseFacts
from redline.pdf_text import PDFText, extract_pdf_text
from redline.report import FailOn, build_report
from redline.rules import validate_rules
from redline.thread_distill import merge_deal_sheets, run_thread_distill


def check_lease(
    path: str | Path,
    *,
    deal_path: str | Path | None = None,
    thread_path: str | Path | None = None,
    context: str | None = None,
    fail_on: FailOn = "error",
    provider: str | None = None,
    model: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> CheckReport:
    pdf_text = extract_pdf_text(path)
    facts = extract_facts_from_text(
        pdf_text,
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    yaml_deal = load_deal_sheet(deal_path) if deal_path else None
    watch_items: list[Finding] = []
    provenance: dict[str, str] = {}
    deal = yaml_deal
    if thread_path is not None:
        try:
            thread_text = Path(thread_path).read_text(encoding="utf-8")
        except OSError as exc:
            raise ExtractionError(f"Could not read negotiation thread: {thread_path}") from exc
        distilled, watch_items = run_thread_distill(
            thread_text,
            provider=provider,
            model=model,
            api_key=api_key,
            base_url=base_url,
        )
        deal, provenance = merge_deal_sheets(yaml_deal, distilled)
    return check_extracted_facts(
        facts=facts,
        pdf_text=pdf_text,
        deal=deal,
        deal_provenance=provenance,
        watch_items=watch_items,
        context=context,
        fail_on=fail_on,
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )


def check_extracted_facts(
    *,
    facts: LeaseFacts,
    pdf_text: PDFText | None = None,
    deal: DealSheet | None = None,
    deal_provenance: dict[str, str] | None = None,
    watch_items: list[Finding] | None = None,
    context: str | None = None,
    fail_on: FailOn = "error",
    provider: str | None = None,
    model: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> CheckReport:
    deterministic = validate_rules(facts, deal)
    advisory: list[Finding] = []
    if context and pdf_text is not None:
        advisory = run_focus_pass(
            facts,
            pdf_text,
            context,
            provider=provider,
            model=model,
            api_key=api_key,
            base_url=base_url,
        )
    if watch_items:
        advisory.extend(watch_items)
    return build_report(
        facts,
        deterministic,
        advisory,
        deal=deal,
        deal_provenance=deal_provenance,
        fail_on=fail_on,
    )
