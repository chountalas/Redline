from __future__ import annotations

from pathlib import Path

import pdfplumber
import pytest

from redline.errors import (
    PdfNotFoundError,
    PdfUnreadableError,
    ScannedPdfError,
)
from redline.pdf_text import extract_pdf_text
from tests.helpers import write_pdf


def test_missing_path_raises_pdf_not_found(tmp_path: Path) -> None:
    missing = tmp_path / "does_not_exist.pdf"

    with pytest.raises(PdfNotFoundError) as excinfo:
        extract_pdf_text(missing)

    assert excinfo.value.code == "pdf_not_found"


def test_unreadable_pdf_raises_pdf_unreadable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    pdf_path = tmp_path / "lease.pdf"
    write_pdf(pdf_path, ["Rent shall be $400,000 per Display Face."])

    def _boom(*_args: object, **_kwargs: object) -> object:
        raise OSError("boom")

    monkeypatch.setattr(pdfplumber, "open", _boom)

    with pytest.raises(PdfUnreadableError) as excinfo:
        extract_pdf_text(pdf_path)

    assert excinfo.value.code == "pdf_unreadable"


def test_no_extractable_text_raises_scanned_pdf(tmp_path: Path) -> None:
    pdf_path = tmp_path / "blank.pdf"
    write_pdf(pdf_path, [])

    with pytest.raises(ScannedPdfError) as excinfo:
        extract_pdf_text(pdf_path)

    assert excinfo.value.code == "scanned_pdf"
