from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from redline.errors import PdfNotFoundError, PdfUnreadableError, ScannedPdfError


@dataclass(frozen=True)
class TextPage:
    page_number: int
    text: str


@dataclass(frozen=True)
class PDFText:
    path: Path
    pages: list[TextPage]

    @property
    def page_count(self) -> int:
        return len(self.pages)

    def as_prompt_text(self) -> str:
        return "\n\n".join(
            f"--- PAGE {page.page_number} ---\n{page.text.strip()}" for page in self.pages
        )


def extract_pdf_text(path: str | Path) -> PDFText:
    pdf_path = Path(path)
    if not pdf_path.exists():
        raise PdfNotFoundError(f"PDF not found: {pdf_path}")
    try:
        import pdfplumber
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("pdfplumber is required for PDF extraction.") from exc

    pages: list[TextPage] = []
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for index, page in enumerate(pdf.pages, start=1):
                text = page.extract_text() or ""
                pages.append(TextPage(page_number=index, text=text))
    except OSError as exc:
        raise PdfUnreadableError(f"Could not read PDF: {pdf_path}") from exc

    if not any(page.text.strip() for page in pages):
        raise ScannedPdfError(
            "This PDF has no extractable text and looks scanned; OCR is unsupported in v1."
        )
    return PDFText(path=pdf_path, pages=pages)
