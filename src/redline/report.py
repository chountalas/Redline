from __future__ import annotations

from collections.abc import Iterable
from typing import Any, Literal

from redline.models import (
    CheckReport,
    CoverageItem,
    DealSheet,
    DealTermCheck,
    DocumentMeta,
    Finding,
    LeaseFacts,
    Money,
    Severity,
    Summary,
)
from redline.profiles import DEFAULT_PROFILE, ProfileID, normalize_profile, profile_meta
from redline.rules import format_money

FailOn = Literal["error", "warn", "verify", "advisory"]


def facts_summary(facts: LeaseFacts) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "source_file": facts.source_file,
        "page_count": facts.page_count,
        "stated_total_rent": None,
        "rent_basis": facts.rent_basis.value,
        "per_face_rent": None,
        "num_display_faces": facts.num_display_faces.value,
        "base_term_years": str(facts.base_term_years.value)
        if facts.base_term_years.value is not None
        else None,
    }
    if facts.stated_total_rent.value is not None:
        summary["stated_total_rent"] = format_money(facts.stated_total_rent.value)
    if facts.per_face_rent.value is not None:
        summary["per_face_rent"] = format_money(facts.per_face_rent.value)
    if facts.security_deposit.value is not None:
        summary["security_deposit"] = format_money(facts.security_deposit.value)
    if facts.default_cure_period_days.value is not None:
        summary["default_cure_period_days"] = facts.default_cure_period_days.value
    if facts.renewal_notice_deadline_days.value is not None:
        summary["renewal_notice_deadline_days"] = facts.renewal_notice_deadline_days.value
    if facts.permitted_use.value is not None:
        summary["permitted_use"] = facts.permitted_use.value
    if facts.assignment_sublease_consent.value is not None:
        summary["assignment_sublease_consent"] = facts.assignment_sublease_consent.value
    return summary


def exit_code_for(
    deterministic_findings: Iterable[Finding],
    advisory_findings: Iterable[Finding],
    fail_on: FailOn = "error",
) -> int:
    deterministic = list(deterministic_findings)
    advisory = list(advisory_findings)
    if fail_on == "error":
        failed = any(f.severity == Severity.ERROR for f in deterministic)
    elif fail_on == "warn":
        failed = any(f.severity in {Severity.ERROR, Severity.WARN} for f in deterministic)
    elif fail_on == "verify":
        failed = any(
            f.severity in {Severity.ERROR, Severity.WARN, Severity.COULD_NOT_VERIFY}
            for f in deterministic
        )
    elif fail_on == "advisory":
        failed = any(
            f.severity in {Severity.ERROR, Severity.WARN, Severity.COULD_NOT_VERIFY}
            for f in deterministic
        ) or bool(advisory)
    else:  # pragma: no cover
        raise ValueError(f"Unknown fail-on value: {fail_on}")
    return 1 if failed else 0


DEAL_FIELD_LABELS = {
    "total_rent": "Total rent",
    "per_face_rent": "Per-face rent",
    "num_display_faces": "Display faces",
    "base_term_years": "Base term (years)",
    "renewal_options": "Renewal options",
    "escalation_pct": "Escalation %",
}


def _format_deal_value(field: str, value: object) -> str:
    if field in ("total_rent", "per_face_rent") and isinstance(value, Money):
        return format_money(value)
    if field == "renewal_options" and isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value)


def build_deal_terms(
    deal: DealSheet | None,
    provenance: dict[str, str],
    r6_findings: list[Finding],
) -> list[DealTermCheck]:
    """Derive the deal-terms checklist from the merged DealSheet + R6's findings.

    Pure presentation of R6 — NEVER an input to exit_code_for. A populated DealSheet field
    with no matching R6 ERROR/COULD_NOT_VERIFY finding is 'verified' (R6 emits nothing on a
    match). R6 finding titles contain the raw field key, so we match on that substring.
    """
    if deal is None:
        return []
    terms: list[DealTermCheck] = []
    for field, label in DEAL_FIELD_LABELS.items():
        value = getattr(deal, field)
        if value is None:
            continue
        match = next((f for f in r6_findings if field in f.title), None)
        verified: bool
        actual: str | None
        if match is None:
            verified, actual = True, _format_deal_value(field, value)
        else:
            verified, actual = False, match.actual
        terms.append(
            DealTermCheck(
                label=label,
                expected=_format_deal_value(field, value),
                actual=actual,
                verified=verified,
                source=provenance.get(field, "deal.yaml"),
            )
        )
    return terms


def build_report(
    facts: LeaseFacts,
    deterministic_findings: list[Finding],
    advisory_findings: list[Finding] | None = None,
    *,
    profile: ProfileID | str = DEFAULT_PROFILE,
    deal: DealSheet | None = None,
    deal_provenance: dict[str, str] | None = None,
    context_summary: str | None = None,
    fail_on: FailOn = "error",
) -> CheckReport:
    resolved_profile = normalize_profile(profile)
    advisory = advisory_findings or []
    all_findings = deterministic_findings + advisory
    r6 = [f for f in deterministic_findings if f.rule_id == "R6_dealsheet_match"]
    return CheckReport(
        profile=profile_meta(resolved_profile),
        document=DocumentMeta(source_file=facts.source_file, page_count=facts.page_count),
        context_summary=context_summary,
        coverage=_coverage(resolved_profile, deal, context_summary),
        facts_summary=facts_summary(facts),
        deterministic_findings=deterministic_findings,
        advisory_findings=advisory,
        could_not_verify=[
            finding
            for finding in deterministic_findings
            if finding.severity == Severity.COULD_NOT_VERIFY
        ],
        deal_terms=build_deal_terms(deal, deal_provenance or {}, r6),
        summary=Summary.from_findings(all_findings),
        exit_code=exit_code_for(deterministic_findings, advisory, fail_on),
    )


def _coverage(
    profile: ProfileID,
    deal: DealSheet | None,
    context_summary: str | None,
) -> list[CoverageItem]:
    items = [
        CoverageItem(
            label="Lease financials and dates",
            status="ran",
            detail=(
                "Ran deterministic rent, term, date, numeral, escalation, "
                "and comparison-term checks."
            ),
        ),
        CoverageItem(
            label="Comparison terms",
            status="ran" if deal is not None else "not_provided",
            detail=(
                "Compared extracted lease facts against supplied numeric comparison terms "
                "when provided."
            ),
        ),
        CoverageItem(
            label="Advisory context",
            status="ran" if context_summary else "not_provided",
            detail="Used review context for non-deterministic advisory findings when provided.",
        ),
    ]
    if profile == "lease-general":
        items.insert(
            1,
            CoverageItem(
                label="General lease clauses",
                status="ran",
                detail=(
                    "Checked extracted permitted use, assignment/sublease, maintenance, "
                    "insurance, default cure, notices, renewal deadlines, additional rent, "
                    "and termination-right visibility."
                ),
            ),
        )
    else:
        items.insert(
            1,
            CoverageItem(
                label="General lease clauses",
                status="not_supported",
                detail="Use profile=lease-general for broader lease clause coverage.",
            ),
        )
    return items


def render_text(report: CheckReport) -> str:
    lines: list[str] = []
    lines.append(f"Profile — {report.profile.name} ({report.profile.id})")
    if report.document:
        lines.append(
            f"Document — {report.document.source_file} ({report.document.page_count} pages)"
        )
    if report.context_summary:
        lines.append(f"Context — {report.context_summary}")
    if report.coverage:
        lines.append("Coverage")
        for item in report.coverage:
            lines.append(f"- [{item.status}] {item.label}: {item.detail}")
    lines.append("")

    deterministic = [
        finding
        for finding in report.deterministic_findings
        if finding.severity != Severity.COULD_NOT_VERIFY
    ]
    could_not_verify = report.could_not_verify

    if not deterministic and not could_not_verify:
        lines.append("No deterministic problems found. All configured checks ran.")
    else:
        for severity in (Severity.ERROR, Severity.WARN, Severity.INFO):
            grouped = [finding for finding in deterministic if finding.severity == severity]
            if grouped:
                lines.append(severity.value)
                lines.extend(_render_findings(grouped))
                lines.append("")
        if could_not_verify:
            lines.append(Severity.COULD_NOT_VERIFY.value)
            lines.extend(_render_findings(could_not_verify))
            lines.append("")

    if report.advisory_findings:
        lines.append("Advisory (AI judgment)")
        lines.extend(_render_findings(report.advisory_findings))
        lines.append("")

    if report.deal_terms:
        verified = sum(1 for t in report.deal_terms if t.verified)
        lines.append(f"Comparison terms — {verified} of {len(report.deal_terms)} verified")
        for term in report.deal_terms:
            mark = "OK" if term.verified else "MISMATCH"
            actual = f", document shows {term.actual}" if term.actual else ""
            lines.append(
                f"- [{mark}] {term.label}: expected {term.expected}{actual} (from {term.source})"
            )
        lines.append("")

    lines.append(_summary_line(report.summary))
    return "\n".join(lines).rstrip() + "\n"


def _render_findings(findings: list[Finding]) -> list[str]:
    lines: list[str] = []
    for finding in findings:
        lines.append(f"- [{finding.rule_id}] {finding.title}")
        lines.append(f"  {finding.detail}")
        if finding.expected is not None:
            lines.append(f"  Expected: {finding.expected}")
        if finding.actual is not None:
            lines.append(f"  Actual: {finding.actual}")
        for evidence in finding.evidence:
            if evidence.quote:
                page = f"p. {evidence.page}" if evidence.page is not None else "page unknown"
                quote = evidence.quote.replace("\n", " ").strip()
                lines.append(f'  Evidence: {page}: "{quote}"')
    return lines


def _summary_line(summary: Summary) -> str:
    parts = [
        f"{summary.error} ERROR",
        f"{summary.warn} WARN",
        f"{summary.could_not_verify} COULD_NOT_VERIFY",
    ]
    if summary.info:
        parts.append(f"{summary.info} INFO")
    if summary.advisory:
        parts.append(f"{summary.advisory} ADVISORY")
    return " | ".join(parts)
