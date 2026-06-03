from __future__ import annotations

from datetime import date
from decimal import Decimal

from redline.models import (
    CheckReport,
    DealSheet,
    DealTermCheck,
    ExtractedValue,
    Finding,
    LeaseFacts,
    Money,
    ScheduleLine,
    Severity,
    Summary,
)
from redline.report import build_deal_terms, build_report, render_text
from redline.rules import validate_rules
from tests.test_rules import facts


def test_deal_term_check_round_trips_and_defaults() -> None:
    term = DealTermCheck(
        label="Total rent", expected="CAD 600,000.00", actual="CAD 600,000.00",
        verified=True, source="thread",
    )
    dumped = term.model_dump(mode="json")
    assert DealTermCheck.model_validate(dumped) == term
    report = CheckReport(
        facts_summary={}, deterministic_findings=[], advisory_findings=[],
        could_not_verify=[], summary=Summary.from_findings([]), exit_code=0,
    )
    assert report.deal_terms == []


def test_report_separates_could_not_verify_and_exit_code() -> None:
    facts = LeaseFacts(
        source_file="synthetic.pdf",
        page_count=1,
        stated_total_rent=ExtractedValue[Money](
            value=Money(amount=Decimal("400000"), currency="CAD")
        ),
        rent_schedule=[],
        commencement_date=ExtractedValue[date](value=date(2026, 1, 1)),
        base_term_years=ExtractedValue[Decimal](value=Decimal("1")),
        stated_expiry_date=ExtractedValue[date](value=date(2026, 12, 31)),
        amount_word_pairs=[],
    )

    findings = validate_rules(facts)
    report = build_report(facts, findings, fail_on="verify")
    text = render_text(report)

    assert report.exit_code == 1
    assert report.could_not_verify
    assert "COULD_NOT_VERIFY" in text


def test_report_error_threshold_ignores_could_not_verify() -> None:
    facts = LeaseFacts(
        source_file="synthetic.pdf",
        page_count=1,
        stated_total_rent=ExtractedValue[Money](
            value=Money(amount=Decimal("400000"), currency="CAD")
        ),
        rent_schedule=[
            ScheduleLine(label="Year 1", amount=Money(amount=Decimal("400000"), currency="CAD"))
        ],
        amount_word_pairs=[],
    )

    report = build_report(facts, validate_rules(facts), fail_on="error")

    assert report.exit_code == 0


def test_thread_numeric_mismatch_is_deterministic_error() -> None:
    deal = DealSheet(total_rent=Money(amount=Decimal("450000"), currency="CAD"))
    deterministic = validate_rules(facts(), deal)
    report = build_report(
        facts(), deterministic, [], deal=deal,
        deal_provenance={"total_rent": "thread"}, fail_on="error",
    )
    assert report.exit_code == 1
    term = next(t for t in report.deal_terms if t.label == "Total rent")
    assert term.verified is False
    assert term.source == "thread"
    assert term.expected == "CAD 450,000.00"


def test_watch_items_never_gate_default_threshold() -> None:
    watch = [
        Finding(
            rule_id="ADVISORY_thread", severity=Severity.ADVISORY,
            title="Exclusivity promised", detail="…",
        )
    ]
    deterministic = validate_rules(facts())
    at_default = build_report(facts(), deterministic, watch, fail_on="error")
    assert at_default.exit_code == 0
    strict = build_report(facts(), deterministic, watch, fail_on="advisory")
    assert strict.exit_code == 1


def test_build_deal_terms_marks_verified_when_no_r6_finding() -> None:
    deal = DealSheet(total_rent=Money(amount=Decimal("400000"), currency="CAD"))
    r6 = validate_rules(facts(), deal)
    terms = build_deal_terms(deal, {"total_rent": "deal.yaml"}, r6)
    assert len(terms) == 1
    assert terms[0].verified is True
    assert terms[0].actual == "CAD 400,000.00"


def test_build_deal_terms_could_not_verify_when_lease_missing_value() -> None:
    deal = DealSheet(base_term_years=Decimal("5"))
    lease = facts(base_term_years=ExtractedValue[Decimal](value=None))
    r6 = validate_rules(lease, deal)
    terms = build_deal_terms(deal, {"base_term_years": "thread"}, r6)
    assert terms[0].verified is False
    assert terms[0].actual is None
    assert terms[0].expected == "5"


def test_build_deal_terms_mixed_verified_and_mismatch() -> None:
    deal = DealSheet(
        total_rent=Money(amount=Decimal("400000"), currency="CAD"),  # matches fixture (400000)
        num_display_faces=99,                                        # mismatches fixture (2)
    )
    r6 = validate_rules(facts(), deal)
    terms = {t.label: t for t in build_deal_terms(deal, {}, r6)}
    assert terms["Total rent"].verified is True
    assert terms["Display faces"].verified is False
    assert terms["Total rent"].source == "thread"  # provenance default
