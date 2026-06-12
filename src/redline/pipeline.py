from __future__ import annotations

from pathlib import Path

from redline.deal import load_deal_sheet
from redline.errors import ExtractionError
from redline.extractor import extract_facts_from_text
from redline.focus import run_focus_pass
from redline.models import CheckReport, DealSheet, Finding, LeaseFacts
from redline.pdf_text import PDFText, extract_pdf_text
from redline.profiles import DEFAULT_PROFILE, ProfileID, normalize_profile
from redline.report import FailOn, build_report
from redline.rules import validate_rules
from redline.thread_distill import DEAL_FIELDS, merge_deal_sheets, run_thread_distill


def check_lease(
    path: str | Path,
    *,
    profile: ProfileID | str = DEFAULT_PROFILE,
    deal_path: str | Path | None = None,
    thread_path: str | Path | None = None,
    context: str | None = None,
    context_path: str | Path | None = None,
    fail_on: FailOn = "error",
    provider: str | None = None,
    model: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> CheckReport:
    resolved_profile = normalize_profile(profile)
    yaml_deal = load_deal_sheet(deal_path) if deal_path else None
    provenance = _deal_sheet_provenance(yaml_deal, "deal.yaml")
    thread_text = _load_negotiation_thread(thread_path) if thread_path else None
    context_text = _load_review_context(context_path) if context_path else None
    pdf_text = extract_pdf_text(path)
    facts = extract_facts_from_text(
        pdf_text,
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
    )
    watch_items: list[Finding] = []
    deal = yaml_deal
    if thread_text is not None:
        distilled, watch_items = run_thread_distill(
            thread_text,
            provider=provider,
            model=model,
            api_key=api_key,
            base_url=base_url,
        )
        deal, provenance = merge_deal_sheets(yaml_deal, distilled)
    advisory_context = _build_advisory_context(
        focus=context,
        context_text=context_text,
        thread_text=thread_text,
    )
    return check_extracted_facts(
        facts=facts,
        pdf_text=pdf_text,
        profile=resolved_profile,
        deal=deal,
        deal_provenance=provenance,
        watch_items=watch_items,
        context=advisory_context,
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
    profile: ProfileID | str = DEFAULT_PROFILE,
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
    resolved_profile = normalize_profile(profile)
    deterministic = validate_rules(facts, deal, profile=resolved_profile)
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
        profile=resolved_profile,
        deal=deal,
        deal_provenance=deal_provenance,
        context_summary=_context_summary(context),
        fail_on=fail_on,
    )


def _load_negotiation_thread(path: str | Path | None) -> str | None:
    if path is None:
        return None
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ExtractionError(f"Could not read negotiation thread: {path}") from exc


def _load_review_context(path: str | Path) -> str:
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ExtractionError(f"Could not read review context: {path}") from exc


def _deal_sheet_provenance(deal: DealSheet | None, source: str) -> dict[str, str]:
    if deal is None:
        return {}
    return {field: source for field in DEAL_FIELDS if getattr(deal, field, None) is not None}


def _build_advisory_context(
    *,
    focus: str | None,
    context_text: str | None,
    thread_text: str | None,
) -> str | None:
    parts: list[str] = []
    if focus and focus.strip():
        parts.append("Focus note:\n" + focus.strip())
    if context_text and context_text.strip():
        parts.append("Review context:\n" + context_text.strip())
    elif thread_text and thread_text.strip():
        parts.append("Review context:\n" + thread_text.strip())
    if not parts:
        return None
    return "\n\n".join(parts)


def _context_summary(context: str | None) -> str | None:
    if not context or not context.strip():
        return None
    return (
        "Review context was provided for advisory analysis; "
        "full context text is not included in this report."
    )
