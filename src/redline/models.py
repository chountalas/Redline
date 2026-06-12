from __future__ import annotations

import re
from datetime import date
from decimal import Decimal
from enum import StrEnum
from typing import Any, Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

T = TypeVar("T")
RentBasis = Literal["per_face", "total", "unknown"]


class RedlineModel(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        arbitrary_types_allowed=True,
    )


class Severity(StrEnum):
    ERROR = "ERROR"
    WARN = "WARN"
    INFO = "INFO"
    COULD_NOT_VERIFY = "COULD_NOT_VERIFY"
    ADVISORY = "ADVISORY"


def _parse_decimal(value: Any) -> Decimal:
    if isinstance(value, Decimal):
        return value
    if isinstance(value, int):
        return Decimal(value)
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, str):
        cleaned = value.strip().replace(",", "").replace("$", "")
        cleaned = re.sub(r"\b(CAD|CDN|USD|US)\b", "", cleaned, flags=re.IGNORECASE).strip()
        return Decimal(cleaned)
    return Decimal(str(value))


class Money(RedlineModel):
    amount: Decimal
    currency: str = "CAD"

    @model_validator(mode="before")
    @classmethod
    def coerce_money(cls, data: Any) -> Any:
        if isinstance(data, Money):
            return data
        if isinstance(data, int | float | Decimal):
            return {"amount": data, "currency": "CAD"}
        if isinstance(data, str):
            text = data.strip()
            currency_match = re.search(r"\b(CAD|CDN|USD|US)\b", text, flags=re.IGNORECASE)
            currency = "CAD"
            if currency_match:
                raw_currency = currency_match.group(1).upper()
                currency = (
                    "CAD"
                    if raw_currency == "CDN"
                    else "USD"
                    if raw_currency == "US"
                    else raw_currency
                )
            amount_match = re.search(r"-?\$?\s*\d[\d,]*(?:\.\d+)?", text)
            if not amount_match:
                return data
            return {"amount": amount_match.group(0), "currency": currency}
        return data

    @field_validator("amount", mode="before")
    @classmethod
    def validate_amount(cls, value: Any) -> Decimal:
        return _parse_decimal(value)

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        normalized = value.upper().strip()
        if normalized == "CDN":
            return "CAD"
        if normalized == "US":
            return "USD"
        return normalized


class ExtractedValue(RedlineModel, Generic[T]):
    value: T | None = None
    quote: str | None = None
    page: int | None = None


class ScheduleLine(RedlineModel):
    label: str
    amount: Money
    quote: str | None = None
    page: int | None = None


class AmountWordPair(RedlineModel):
    numeral: Money
    words: str
    quote: str | None = None
    page: int | None = None


class Evidence(RedlineModel):
    quote: str | None = None
    page: int | None = None


class LeaseFacts(RedlineModel):
    source_file: str
    page_count: int
    stated_total_rent: ExtractedValue[Money] = Field(default_factory=ExtractedValue[Money])
    rent_basis: ExtractedValue[RentBasis] = Field(default_factory=ExtractedValue[RentBasis])
    per_face_rent: ExtractedValue[Money] = Field(default_factory=ExtractedValue[Money])
    num_display_faces: ExtractedValue[int] = Field(default_factory=ExtractedValue[int])
    rent_schedule: list[ScheduleLine] = Field(default_factory=list)
    escalation_pct: ExtractedValue[Decimal] = Field(default_factory=ExtractedValue[Decimal])
    escalation_clause_present: ExtractedValue[bool] = Field(default_factory=ExtractedValue[bool])
    amount_word_pairs: list[AmountWordPair] = Field(default_factory=list)
    commencement_date: ExtractedValue[date] = Field(default_factory=ExtractedValue[date])
    base_term_years: ExtractedValue[Decimal] = Field(default_factory=ExtractedValue[Decimal])
    renewal_options: ExtractedValue[list[Decimal]] = Field(
        default_factory=ExtractedValue[list[Decimal]]
    )
    stated_expiry_date: ExtractedValue[date] = Field(default_factory=ExtractedValue[date])
    security_deposit: ExtractedValue[Money] = Field(default_factory=ExtractedValue[Money])
    additional_rent_terms: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    cam_audit_rights: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    permitted_use: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    maintenance_responsibility: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    insurance_requirements: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    indemnity_clause: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    assignment_sublease_consent: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    default_cure_period_days: ExtractedValue[int] = Field(default_factory=ExtractedValue[int])
    notice_addresses: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    renewal_notice_deadline_days: ExtractedValue[int] = Field(default_factory=ExtractedValue[int])
    termination_rights: ExtractedValue[str] = Field(default_factory=ExtractedValue[str])
    extraction_notes: str | None = None


class DealSheet(RedlineModel):
    total_rent: Money | None = None
    per_face_rent: Money | None = None
    num_display_faces: int | None = None
    base_term_years: Decimal | None = None
    renewal_options: list[Decimal] | None = None
    escalation_pct: Decimal | None = None

    @field_validator("base_term_years", "escalation_pct", mode="before")
    @classmethod
    def validate_decimal_field(cls, value: Any) -> Decimal | None:
        if value is None:
            return None
        return _parse_decimal(value)

    @field_validator("renewal_options", mode="before")
    @classmethod
    def validate_renewals(cls, value: Any) -> list[Decimal] | None:
        if value is None:
            return None
        if not isinstance(value, list):
            raise TypeError("renewal_options must be a list")
        return [_parse_decimal(item) for item in value]


class DealTermCheck(RedlineModel):
    """A single negotiated numeric term, paired with its deterministic R6 outcome.

    This is a *presentation* of R6's result, never a source of truth for the exit code.
    """

    label: str
    expected: str
    actual: str | None = None
    verified: bool
    source: str  # "deal.yaml" | "thread"


class Finding(RedlineModel):
    rule_id: str
    severity: Severity
    title: str
    detail: str
    evidence: list[Evidence] = Field(default_factory=list)
    expected: str | None = None
    actual: str | None = None


class Summary(RedlineModel):
    error: int = 0
    warn: int = 0
    info: int = 0
    could_not_verify: int = 0
    advisory: int = 0

    @classmethod
    def from_findings(cls, findings: list[Finding]) -> Summary:
        summary = cls()
        for finding in findings:
            if finding.severity == Severity.ERROR:
                summary.error += 1
            elif finding.severity == Severity.WARN:
                summary.warn += 1
            elif finding.severity == Severity.INFO:
                summary.info += 1
            elif finding.severity == Severity.COULD_NOT_VERIFY:
                summary.could_not_verify += 1
            elif finding.severity == Severity.ADVISORY:
                summary.advisory += 1
        return summary


class ProfileMeta(RedlineModel):
    id: str = "lease-general"
    name: str = "General lease"
    version: str = "1"
    description: str = (
        "Commercial lease financial, date, comparison-term, and general clause coverage checks."
    )


class DocumentMeta(RedlineModel):
    source_file: str
    page_count: int
    kind: str = "document_pdf"


class CoverageItem(RedlineModel):
    label: str
    status: Literal["ran", "not_provided", "not_supported"]
    detail: str


class CheckReport(RedlineModel):
    profile: ProfileMeta = Field(default_factory=ProfileMeta)
    document: DocumentMeta | None = None
    context_summary: str | None = None
    coverage: list[CoverageItem] = Field(default_factory=list)
    facts_summary: dict[str, Any]
    deterministic_findings: list[Finding]
    advisory_findings: list[Finding] = Field(default_factory=list)
    could_not_verify: list[Finding] = Field(default_factory=list)
    summary: Summary
    exit_code: int
    deal_terms: list[DealTermCheck] = Field(default_factory=list)
