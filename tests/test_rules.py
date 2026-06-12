from __future__ import annotations

from datetime import date
from decimal import Decimal
from pathlib import Path

from redline.models import (
    AmountWordPair,
    DealSheet,
    ExtractedValue,
    LeaseFacts,
    Money,
    ScheduleLine,
    Severity,
)
from redline.rules import validate_rules


def facts(**overrides: object) -> LeaseFacts:
    base = {
        "source_file": "synthetic.pdf",
        "page_count": 3,
        "stated_total_rent": ExtractedValue[Money](
            value=Money(amount=Decimal("400000"), currency="CAD"),
            quote="$400,000 total rent",
            page=2,
        ),
        "rent_basis": ExtractedValue(value="total", quote="total rent", page=2),
        "per_face_rent": ExtractedValue[Money](
            value=Money(amount=Decimal("200000"), currency="CAD"),
            quote="$200,000 per Display Face",
            page=2,
        ),
        "num_display_faces": ExtractedValue[int](value=2, quote="two display faces", page=1),
        "rent_schedule": [
            ScheduleLine(
                label="Year 1",
                amount=Money(amount=Decimal("200000"), currency="CAD"),
                quote="Year 1 - $200,000",
                page=2,
            ),
            ScheduleLine(
                label="Year 2",
                amount=Money(amount=Decimal("200000"), currency="CAD"),
                quote="Year 2 - $200,000",
                page=2,
            ),
        ],
        "escalation_pct": ExtractedValue[Decimal](value=None, quote=None, page=None),
        "escalation_clause_present": ExtractedValue[bool](
            value=False,
            quote="No annual escalation applies.",
            page=2,
        ),
        "amount_word_pairs": [
            AmountWordPair(
                numeral=Money(amount=Decimal("400000"), currency="CAD"),
                words="Four Hundred Thousand Dollars",
                quote="$400,000 (Four Hundred Thousand Dollars)",
                page=2,
            )
        ],
        "commencement_date": ExtractedValue[date](
            value=date(2026, 1, 1),
            quote="commences January 1, 2026",
            page=1,
        ),
        "base_term_years": ExtractedValue[Decimal](
            value=Decimal("2"), quote="two year term", page=1
        ),
        "renewal_options": ExtractedValue[list[Decimal]](
            value=[Decimal("5")], quote="one five-year renewal", page=1
        ),
        "stated_expiry_date": ExtractedValue[date](
            value=date(2027, 12, 31),
            quote="expires December 31, 2027",
            page=1,
        ),
    }
    base.update(overrides)
    return LeaseFacts.model_validate(base)


def by_rule(findings, rule_id: str):
    return [finding for finding in findings if finding.rule_id == rule_id]


def test_clean_synthetic_facts_only_emit_info_for_lease_math_profile() -> None:
    findings = validate_rules(facts(), profile="lease-math")

    assert [finding.severity for finding in findings] == [Severity.INFO]
    assert findings[0].rule_id == "R5_term_date_coherence"


def test_r5_total_exposure_avoids_scientific_notation() -> None:
    # Regression: Decimal("20").normalize() is Decimal("2E+1"); the term-exposure INFO line
    # must read "20 years", not "2E+1 years" (a 15yr base + one 5yr renewal = 20).
    lease_facts = facts(
        base_term_years=ExtractedValue[Decimal](
            value=Decimal("15"), quote="fifteen (15) years", page=2
        ),
        renewal_options=ExtractedValue[list[Decimal]](
            value=[Decimal("5")], quote="a 5-year renewal", page=2
        ),
    )
    info = [
        finding
        for finding in by_rule(validate_rules(lease_facts), "R5_term_date_coherence")
        if finding.severity == Severity.INFO
    ]
    assert len(info) == 1
    assert info[0].actual == "20 years"


def test_r1_flags_schedule_total_mismatch() -> None:
    lease_facts = facts(
        rent_schedule=[
            ScheduleLine(
                label="Year 1",
                amount=Money(amount=Decimal("100000"), currency="CAD"),
                quote="Year 1",
                page=2,
            ),
            ScheduleLine(
                label="Year 2",
                amount=Money(amount=Decimal("100000"), currency="CAD"),
                quote="Year 2",
                page=2,
            ),
        ]
    )

    finding = by_rule(validate_rules(lease_facts), "R1_schedule_sums_to_total")[0]

    assert finding.severity == Severity.ERROR
    assert finding.expected == "CAD 400,000.00"
    assert finding.actual == "CAD 200,000.00"


def test_r2_catches_pembina_class_per_face_total_error() -> None:
    lease_facts = facts(
        rent_basis=ExtractedValue(value="per_face", quote="$400,000 per Display Face", page=2),
        per_face_rent=ExtractedValue[Money](
            value=Money(amount=Decimal("400000"), currency="CAD"),
            quote="$400,000 per Display Face",
            page=2,
        ),
        num_display_faces=ExtractedValue[int](value=2, quote="two Display Faces", page=1),
        stated_total_rent=ExtractedValue[Money](
            value=Money(amount=Decimal("400000"), currency="CAD"),
            quote="Total rent shall be $400,000",
            page=2,
        ),
    )

    finding = by_rule(validate_rules(lease_facts), "R2_per_face_total_reconcile")[0]

    assert finding.severity == Severity.ERROR
    assert finding.expected == "CAD 800,000.00"
    assert finding.actual == "CAD 400,000.00"
    assert finding.evidence


def test_r3_warns_when_escalation_clause_but_flat_schedule() -> None:
    lease_facts = facts(
        escalation_pct=ExtractedValue[Decimal](
            value=Decimal("2"), quote="2% annual escalation", page=2
        ),
        escalation_clause_present=ExtractedValue[bool](
            value=True, quote="2% annual escalation", page=2
        ),
    )

    finding = by_rule(validate_rules(lease_facts), "R3_escalation_consistency")[0]

    assert finding.severity == Severity.WARN
    assert finding.actual == "flat schedule"


def test_r4_flags_numeral_words_mismatch() -> None:
    lease_facts = facts(
        amount_word_pairs=[
            AmountWordPair(
                numeral=Money(amount=Decimal("800000"), currency="CAD"),
                words="Four Hundred Thousand Dollars",
                quote="$800,000 (Four Hundred Thousand Dollars)",
                page=2,
            )
        ]
    )

    finding = by_rule(validate_rules(lease_facts), "R4_numeral_vs_words")[0]

    assert finding.severity == Severity.ERROR
    assert finding.expected == "CAD 400,000.00"
    assert finding.actual == "CAD 800,000.00"


def test_r5_flags_bad_expiry_date_and_keeps_exposure_info() -> None:
    lease_facts = facts(
        stated_expiry_date=ExtractedValue[date](
            value=date(2028, 1, 1),
            quote="expires January 1, 2028",
            page=1,
        )
    )

    findings = by_rule(validate_rules(lease_facts), "R5_term_date_coherence")

    assert findings[0].severity == Severity.INFO
    assert findings[1].severity == Severity.ERROR
    assert findings[1].expected == "2027-12-31"
    assert findings[1].actual == "2028-01-01"


def test_missing_inputs_emit_could_not_verify() -> None:
    lease_facts = facts(rent_schedule=[])

    finding = by_rule(validate_rules(lease_facts), "R1_schedule_sums_to_total")[0]

    assert finding.severity == Severity.COULD_NOT_VERIFY


def test_r6_compares_deal_sheet() -> None:
    lease_facts = facts()
    deal = DealSheet(
        total_rent=Money(amount=Decimal("450000"), currency="CAD"), num_display_faces=2
    )

    finding = by_rule(validate_rules(lease_facts, deal), "R6_dealsheet_match")[0]

    assert finding.severity == Severity.ERROR
    assert finding.expected == "CAD 450,000.00"
    assert finding.actual == "CAD 400,000.00"


def test_pembina_fixture_has_exact_r2_error() -> None:
    fixture = Path(__file__).parent / "fixtures" / "pembina_per_face_facts.json"
    lease_facts = LeaseFacts.model_validate_json(fixture.read_text(encoding="utf-8"))

    finding = by_rule(validate_rules(lease_facts), "R2_per_face_total_reconcile")[0]

    assert finding.severity == Severity.ERROR
    assert finding.expected == "CAD 800,000.00"
    assert finding.actual == "CAD 400,000.00"


def test_default_profile_adds_general_clause_coverage() -> None:
    findings = validate_rules(facts())

    coverage = by_rule(findings, "R7_general_lease_clause_coverage")

    assert coverage
    assert any(f.title == "Could not verify permitted use" for f in coverage)


def test_lease_math_profile_excludes_general_clause_coverage() -> None:
    findings = validate_rules(facts(), profile="lease-math")

    assert not by_rule(findings, "R7_general_lease_clause_coverage")


def test_lease_general_warns_on_renewal_without_notice_deadline() -> None:
    lease_facts = facts(
        renewal_options=ExtractedValue[list[Decimal]](
            value=[Decimal("5")], quote="Tenant has one five-year renewal option.", page=4
        ),
        renewal_notice_deadline_days=ExtractedValue[int](value=None),
    )

    finding = by_rule(
        validate_rules(lease_facts, profile="lease-general"),
        "R8_renewal_notice_window",
    )[0]

    assert finding.severity == Severity.WARN
    assert "notice deadline" in finding.title


def test_lease_general_warns_on_additional_rent_without_audit_rights() -> None:
    lease_facts = facts(
        additional_rent_terms=ExtractedValue[str](
            value="Tenant shall pay its proportionate share of operating expenses.",
            quote="Tenant shall pay its proportionate share of operating expenses.",
            page=7,
        ),
        cam_audit_rights=ExtractedValue[str](value=None),
    )

    finding = by_rule(
        validate_rules(lease_facts, profile="lease-general"),
        "R9_additional_rent_audit_visibility",
    )[0]

    assert finding.severity == Severity.WARN
    assert "audit rights" in finding.title


def test_lease_general_warns_on_discretionary_assignment_consent() -> None:
    lease_facts = facts(
        assignment_sublease_consent=ExtractedValue[str](
            value=(
                "Tenant may not assign without Landlord's consent, which may be withheld "
                "in Landlord's sole discretion."
            ),
            quote="withheld in Landlord's sole discretion",
            page=8,
        )
    )

    finding = by_rule(
        validate_rules(lease_facts, profile="lease-general"),
        "R10_assignment_consent_standard",
    )[0]

    assert finding.severity == Severity.WARN
