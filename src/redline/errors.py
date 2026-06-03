from __future__ import annotations

from typing import ClassVar


class RedlineError(Exception):
    """Base exception for expected Redline failures."""

    code: ClassVar[str] = "error"


class ScannedPdfError(RedlineError):
    """Raised when a PDF has extractable-text pages but none contain text (looks scanned)."""

    code: ClassVar[str] = "scanned_pdf"


class PdfNotFoundError(RedlineError):
    """Raised when the PDF path does not exist."""

    code: ClassVar[str] = "pdf_not_found"


class PdfUnreadableError(RedlineError):
    """Raised when the PDF exists but cannot be read/parsed at the filesystem level."""

    code: ClassVar[str] = "pdf_unreadable"


class ExtractionError(RedlineError):
    """Raised when LLM extraction fails or returns invalid data."""

    code: ClassVar[str] = "extraction_failed"


class DealSheetError(RedlineError):
    """Raised when deal.yaml cannot be parsed or validated."""

    code: ClassVar[str] = "deal_sheet_invalid"
