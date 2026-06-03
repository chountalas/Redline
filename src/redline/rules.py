from __future__ import annotations

from collections.abc import Callable
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from dateutil.relativedelta import relativedelta

from redline.models import (
    AmountWordPair,
    DealSheet,
    Evidence,
    ExtractedValue,
    Finding,
    LeaseFacts,
    Money,
    ScheduleLine,
    Severity,
)
from redline.money_words import parse_money_words

Rule = Callable[[LeaseFacts, DealSheet | None], list[Finding]]
MONEY_TOLERANCE = Decimal("1.00")


def format_money(money: Money | Decimal, currency: str = "CAD") -> str:
    if isinstance(money, Money):
        amount = money.amount
        currency = money.currency
    else:
        amount = money
    quantized = amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"{currency} {quantized:,.2f}"


def _money_close(left: Money, right: Money, tolerance: Decimal = MONEY_TOLERANCE) -> bool:
    return left.currency == right.currency and abs(left.amount - right.amount) <= tolerance


def _decimal_close(left: Decimal, right: Decimal, tolerance: Decimal = Decimal("0.0001")) -> bool:
    return abs(left - right) <= tolerance


def _evidence_from(*items: object) -> list[Evidence]:
    evidence: list[Evidence] = []
    for item in items:
        if isinstance(item, ExtractedValue | ScheduleLine | AmountWordPair):
            if item.quote or item.page is not None:
                evidence.append(Evidence(quote=item.quote, page=item.page))
        elif isinstance(item, list):
            evidence.extend(_evidence_from(*item))
    return evidence


def _could_not_verify(
    rule_id: str, title: str, detail: str, evidence: list[Evidence] | None = None
) -> Finding:
    return Finding(
        rule_id=rule_id,
        severity=Severity.COULD_NOT_VERIFY,
        title=title,
        detail=detail,
        evidence=evidence or [],
    )


def r1_schedule_sums_to_total(facts: LeaseFacts, deal: DealSheet | None = None) -> list[Finding]:
    del deal
    rule_id = "R1_schedule_sums_to_total"
    if not facts.rent_schedule:
        return [
            _could_not_verify(
                rule_id,
                "Could not verify rent schedule total",
                "No rent schedule was found in extraction.",
            )
        ]
    if facts.stated_total_rent.value is None:
        return [
            _could_not_verify(
                rule_id,
                "Could not verify rent schedule total",
                "No stated total rent was found in extraction.",
                _evidence_from(facts.rent_schedule),
            )
        ]

    currency = facts.stated_total_rent.value.currency
    mismatched_currency = [
        line.amount.currency for line in facts.rent_schedule if line.amount.currency != currency
    ]
    if mismatched_currency:
        return [
            Finding(
                rule_id=rule_id,
                severity=Severity.ERROR,
                title="Rent schedule uses mixed currencies",
                detail="The rent schedule and stated total rent do not use the same currency.",
                evidence=_evidence_from(facts.stated_total_rent, facts.rent_schedule),
                expected=currency,
                actual=", ".join(sorted(set(mismatched_currency))),
            )
        ]

    schedule_total = sum((line.amount.amount for line in facts.rent_schedule), Decimal("0"))
    actual = Money(amount=schedule_total, currency=currency)
    if not _money_close(actual, facts.stated_total_rent.value):
        return [
            Finding(
                rule_id=rule_id,
                severity=Severity.ERROR,
                title="Rent schedule does not sum to stated total",
                detail="The extracted rent schedule total differs from the stated total rent.",
                evidence=_evidence_from(facts.stated_total_rent, facts.rent_schedule),
                expected=format_money(facts.stated_total_rent.value),
                actual=format_money(actual),
            )
        ]
    return []


def r2_per_face_total_reconcile(facts: LeaseFacts, deal: DealSheet | None = None) -> list[Finding]:
    del deal
    rule_id = "R2_per_face_total_reconcile"
    basis = facts.rent_basis.value
    per_face = facts.per_face_rent.value
    face_count = facts.num_display_faces.value
    stated_total = facts.stated_total_rent.value
    if basis is None or basis == "unknown":
        return [
            _could_not_verify(
                rule_id,
                "Could not verify per-face rent",
                "Rent basis was missing or unknown.",
                _evidence_from(facts.rent_basis),
            )
        ]

    if basis != "per_face":
        return []

    if per_face is None or face_count is None or stated_total is None:
        return [
            _could_not_verify(
                rule_id,
                "Could not verify per-face rent",
                "Per-face rent, display face count, or stated total rent was missing.",
                _evidence_from(
                    facts.per_face_rent,
                    facts.num_display_faces,
                    facts.stated_total_rent,
                ),
            )
        ]

    faces = Decimal(face_count)
    expected = Money(amount=per_face.amount * faces, currency=per_face.currency)
    if not _money_close(expected, stated_total):
        return [
            Finding(
                rule_id=rule_id,
                severity=Severity.ERROR,
                title="Per-face rent does not reconcile to stated total",
                detail=(
                    "The lease appears to apply a rent figure per display face, but the "
                    "stated total does not equal per-face rent times display faces."
                ),
                evidence=_evidence_from(
                    facts.rent_basis,
                    facts.per_face_rent,
                    facts.num_display_faces,
                    facts.stated_total_rent,
                ),
                expected=format_money(expected),
                actual=format_money(stated_total),
            )
        ]
    return []


def r3_escalation_consistency(facts: LeaseFacts, deal: DealSheet | None = None) -> list[Finding]:
    del deal
    rule_id = "R3_escalation_consistency"
    if len(facts.rent_schedule) < 2:
        return [
            _could_not_verify(
                rule_id,
                "Could not verify escalation consistency",
                "At least two rent schedule lines are required to verify escalation.",
                _evidence_from(facts.rent_schedule),
            )
        ]

    pct = facts.escalation_pct.value
    clause_present = facts.escalation_clause_present.value
    amounts = [line.amount for line in facts.rent_schedule]
    all_flat = all(_money_close(amounts[0], amount) for amount in amounts[1:])
    any_change = any(not _money_close(amounts[0], amount) for amount in amounts[1:])

    if pct is None:
        if clause_present is False and any_change:
            return [
                Finding(
                    rule_id=rule_id,
                    severity=Severity.WARN,
                    title="Rent schedule escalates without an escalation clause",
                    detail=(
                        "Scheduled rent changes, but extraction did not find an escalation clause."
                    ),
                    evidence=_evidence_from(facts.escalation_clause_present, facts.rent_schedule),
                )
            ]
        if clause_present is True:
            return [
                _could_not_verify(
                    rule_id,
                    "Could not verify escalation percentage",
                    "An escalation clause was found, but no escalation percentage was extracted.",
                    _evidence_from(facts.escalation_clause_present, facts.rent_schedule),
                )
            ]
        return []

    if pct > 0 and all_flat:
        return [
            Finding(
                rule_id=rule_id,
                severity=Severity.WARN,
                title="Escalation clause is present but rent schedule is flat",
                detail=(
                    "The extracted escalation percentage is positive, but all scheduled "
                    "rent values are equal."
                ),
                evidence=_evidence_from(facts.escalation_pct, facts.rent_schedule),
                expected=f"{pct}% annual escalation",
                actual="flat schedule",
            )
        ]

    rate = pct / Decimal("100")
    findings: list[Finding] = []
    for previous, current in zip(facts.rent_schedule, facts.rent_schedule[1:], strict=False):
        expected_amount = previous.amount.amount * (Decimal("1") + rate)
        expected = Money(amount=expected_amount, currency=previous.amount.currency)
        if not _money_close(expected, current.amount):
            findings.append(
                Finding(
                    rule_id=rule_id,
                    severity=Severity.WARN,
                    title="Rent schedule does not match escalation percentage",
                    detail=(
                        f"{current.label} does not equal the prior schedule line "
                        f"escalated by {pct}%."
                    ),
                    evidence=_evidence_from(facts.escalation_pct, previous, current),
                    expected=format_money(expected),
                    actual=format_money(current.amount),
                )
            )
    return findings


def r4_numeral_vs_words(facts: LeaseFacts, deal: DealSheet | None = None) -> list[Finding]:
    del deal
    rule_id = "R4_numeral_vs_words"
    if not facts.amount_word_pairs:
        return [
            _could_not_verify(
                rule_id,
                "Could not verify numeral/word agreement",
                "No numeral/word money pairs were extracted.",
            )
        ]

    findings: list[Finding] = []
    for pair in facts.amount_word_pairs:
        parsed = parse_money_words(pair.words)
        if parsed is None:
            findings.append(
                _could_not_verify(
                    rule_id,
                    "Could not parse money words",
                    f"The words could not be parsed as a money amount: {pair.words!r}.",
                    _evidence_from(pair),
                )
            )
            continue
        expected = Money(amount=parsed, currency=pair.numeral.currency)
        if not _money_close(expected, pair.numeral):
            findings.append(
                Finding(
                    rule_id=rule_id,
                    severity=Severity.ERROR,
                    title="Numeral and words do not match",
                    detail="A money amount's numeral and spelled-out words differ.",
                    evidence=_evidence_from(pair),
                    expected=format_money(expected),
                    actual=format_money(pair.numeral),
                )
            )
    return findings


def _months_from_years(years: Decimal) -> int | None:
    months = years * Decimal("12")
    integral = months.to_integral_value()
    if months != integral:
        return None
    return int(integral)


def r5_term_date_coherence(facts: LeaseFacts, deal: DealSheet | None = None) -> list[Finding]:
    del deal
    rule_id = "R5_term_date_coherence"
    findings: list[Finding] = []
    base_years = facts.base_term_years.value
    renewals = facts.renewal_options.value or []

    if base_years is not None:
        total_exposure = base_years + sum(renewals, Decimal("0"))
        findings.append(
            Finding(
                rule_id=rule_id,
                severity=Severity.INFO,
                title="Total term exposure",
                detail="Base term plus extracted renewal options.",
                evidence=_evidence_from(facts.base_term_years, facts.renewal_options),
                actual=f"{total_exposure.normalize():f} years",
            )
        )

    if (
        facts.commencement_date.value is None
        or base_years is None
        or facts.stated_expiry_date.value is None
    ):
        findings.append(
            _could_not_verify(
                rule_id,
                "Could not verify term dates",
                "Commencement date, base term years, or stated expiry date was missing.",
                _evidence_from(
                    facts.commencement_date,
                    facts.base_term_years,
                    facts.stated_expiry_date,
                ),
            )
        )
        return findings

    months = _months_from_years(base_years)
    if months is None:
        findings.append(
            _could_not_verify(
                rule_id,
                "Could not verify fractional base term",
                "Base term years could not be converted to whole months.",
                _evidence_from(facts.base_term_years),
            )
        )
        return findings

    expected_expiry = (
        facts.commencement_date.value + relativedelta(months=months) - timedelta(days=1)
    )
    if expected_expiry != facts.stated_expiry_date.value:
        findings.append(
            Finding(
                rule_id=rule_id,
                severity=Severity.ERROR,
                title="Term dates do not reconcile",
                detail="Commencement date plus base term does not equal the stated expiry date.",
                evidence=_evidence_from(
                    facts.commencement_date,
                    facts.base_term_years,
                    facts.stated_expiry_date,
                ),
                expected=expected_expiry.isoformat(),
                actual=facts.stated_expiry_date.value.isoformat(),
            )
        )
    return findings


def _compare_money(
    rule_id: str,
    label: str,
    expected: Money,
    extracted: ExtractedValue[Money],
) -> list[Finding]:
    if extracted.value is None:
        return [
            _could_not_verify(
                rule_id,
                f"Could not verify deal sheet {label}",
                f"Deal sheet provided {label}, but the lease extraction did not include it.",
                _evidence_from(extracted),
            )
        ]
    if not _money_close(expected, extracted.value):
        return [
            Finding(
                rule_id=rule_id,
                severity=Severity.ERROR,
                title=f"Deal sheet {label} does not match lease",
                detail=f"The extracted lease value differs from deal.yaml for {label}.",
                evidence=_evidence_from(extracted),
                expected=format_money(expected),
                actual=format_money(extracted.value),
            )
        ]
    return []


def _compare_scalar(
    rule_id: str,
    label: str,
    expected: object,
    extracted: ExtractedValue[Any],
) -> list[Finding]:
    if extracted.value is None:
        return [
            _could_not_verify(
                rule_id,
                f"Could not verify deal sheet {label}",
                f"Deal sheet provided {label}, but the lease extraction did not include it.",
                _evidence_from(extracted),
            )
        ]
    if extracted.value != expected:
        return [
            Finding(
                rule_id=rule_id,
                severity=Severity.ERROR,
                title=f"Deal sheet {label} does not match lease",
                detail=f"The extracted lease value differs from deal.yaml for {label}.",
                evidence=_evidence_from(extracted),
                expected=str(expected),
                actual=str(extracted.value),
            )
        ]
    return []


def r6_dealsheet_match(facts: LeaseFacts, deal: DealSheet | None = None) -> list[Finding]:
    rule_id = "R6_dealsheet_match"
    if deal is None:
        return []

    findings: list[Finding] = []
    if deal.total_rent is not None:
        findings.extend(
            _compare_money(rule_id, "total_rent", deal.total_rent, facts.stated_total_rent)
        )
    if deal.per_face_rent is not None:
        findings.extend(
            _compare_money(rule_id, "per_face_rent", deal.per_face_rent, facts.per_face_rent)
        )
    if deal.num_display_faces is not None:
        findings.extend(
            _compare_scalar(
                rule_id,
                "num_display_faces",
                deal.num_display_faces,
                facts.num_display_faces,
            )
        )
    if deal.base_term_years is not None:
        extracted = facts.base_term_years
        if extracted.value is None:
            findings.append(
                _could_not_verify(
                    rule_id,
                    "Could not verify deal sheet base_term_years",
                    (
                        "Deal sheet provided base_term_years, but the lease extraction "
                        "did not include it."
                    ),
                    _evidence_from(extracted),
                )
            )
        elif not _decimal_close(deal.base_term_years, extracted.value):
            findings.append(
                Finding(
                    rule_id=rule_id,
                    severity=Severity.ERROR,
                    title="Deal sheet base_term_years does not match lease",
                    detail="The extracted lease value differs from deal.yaml for base_term_years.",
                    evidence=_evidence_from(extracted),
                    expected=str(deal.base_term_years),
                    actual=str(extracted.value),
                )
            )
    if deal.renewal_options is not None:
        findings.extend(
            _compare_scalar(
                rule_id,
                "renewal_options",
                deal.renewal_options,
                facts.renewal_options,
            )
        )
    if deal.escalation_pct is not None:
        extracted_pct = facts.escalation_pct
        if extracted_pct.value is None:
            findings.append(
                _could_not_verify(
                    rule_id,
                    "Could not verify deal sheet escalation_pct",
                    (
                        "Deal sheet provided escalation_pct, but the lease extraction "
                        "did not include it."
                    ),
                    _evidence_from(extracted_pct),
                )
            )
        elif not _decimal_close(deal.escalation_pct, extracted_pct.value):
            findings.append(
                Finding(
                    rule_id=rule_id,
                    severity=Severity.ERROR,
                    title="Deal sheet escalation_pct does not match lease",
                    detail="The extracted lease value differs from deal.yaml for escalation_pct.",
                    evidence=_evidence_from(extracted_pct),
                    expected=str(deal.escalation_pct),
                    actual=str(extracted_pct.value),
                )
            )
    return findings


RULES: tuple[Rule, ...] = (
    r1_schedule_sums_to_total,
    r2_per_face_total_reconcile,
    r3_escalation_consistency,
    r4_numeral_vs_words,
    r5_term_date_coherence,
    r6_dealsheet_match,
)


def validate_rules(facts: LeaseFacts, deal: DealSheet | None = None) -> list[Finding]:
    findings: list[Finding] = []
    for rule in RULES:
        findings.extend(rule(facts, deal))
    return findings
