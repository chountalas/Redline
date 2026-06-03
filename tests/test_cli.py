from __future__ import annotations

import json
from pathlib import Path

import pytest

from redline.cli import main
from redline.errors import DealSheetError, ExtractionError
from redline.models import CheckReport, Summary
from tests.helpers import FakeOpenAIClient, synthetic_pembina_facts, text_response, write_pdf


def test_cli_check_runs_pdf_to_json_report(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    pdf_path = tmp_path / "lease.pdf"
    write_pdf(
        pdf_path,
        [
            "The Premises include two Display Faces.",
            "Rent shall be $400,000 per Display Face.",
            "Total rent shall be $400,000.",
        ],
    )
    fake_client = FakeOpenAIClient([text_response(synthetic_pembina_facts(str(pdf_path)))])
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: fake_client,
    )

    exit_code = main(
        ["check", str(pdf_path), "--json", "--provider", "openai", "--model", "openai-test-model"]
    )

    captured = capsys.readouterr()
    assert exit_code == 1
    assert '"rule_id": "R2_per_face_total_reconcile"' in captured.out
    assert '"expected": "CAD 800,000.00"' in captured.out


def test_cli_thread_distill_produces_deal_terms(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    pdf_path = tmp_path / "lease.pdf"
    write_pdf(
        pdf_path,
        [
            "The Premises include two Display Faces.",
            "Rent shall be $400,000 per Display Face.",
            "Total rent shall be $800,000.",
        ],
    )
    thread_path = tmp_path / "thread.txt"
    thread_path.write_text("We agreed total rent is $800,000 across two faces.")

    fake = FakeOpenAIClient(
        [
            text_response(synthetic_pembina_facts(str(pdf_path))),  # 1) extraction
            text_response(  # 2) thread distill
                {
                    "deal_sheet": {"total_rent": "800000", "num_display_faces": 2},
                    "watch_items": [],
                }
            ),
        ]
    )
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        "redline.llm._create_openai_client",
        lambda api_key, base_url=None: fake,
    )

    main(
        [
            "check",
            str(pdf_path),
            "--thread",
            str(thread_path),
            "--json",
            "--provider",
            "openai",
            "--model",
            "openai-test-model",
        ]
    )
    captured = capsys.readouterr()
    assert '"deal_terms"' in captured.out
    assert '"source": "thread"' in captured.out


def test_cli_json_error_emits_envelope_on_stdout_for_missing_pdf(
    capsys: pytest.CaptureFixture[str],
) -> None:
    exit_code = main(["check", "/no/such/file.pdf", "--json"])

    captured = capsys.readouterr()
    assert exit_code == 2
    assert "redline:" in captured.err
    payload = json.loads(captured.out)
    assert payload["error"]["code"] == "pdf_not_found"
    assert isinstance(payload["error"]["message"], str)
    assert payload["error"]["message"]


def test_cli_json_error_envelope_for_extraction_failure(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    def boom(*args: object, **kwargs: object) -> CheckReport:
        raise ExtractionError("boom")

    monkeypatch.setattr("redline.cli.check_lease", boom)

    exit_code = main(["check", "x.pdf", "--json"])

    captured = capsys.readouterr()
    assert exit_code == 2
    payload = json.loads(captured.out)
    assert payload["error"]["code"] == "extraction_failed"
    assert "boom" in payload["error"]["message"]


def test_cli_json_error_envelope_for_deal_sheet_failure(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    def boom(*args: object, **kwargs: object) -> CheckReport:
        raise DealSheetError("bad deal")

    monkeypatch.setattr("redline.cli.check_lease", boom)

    exit_code = main(["check", "x.pdf", "--json"])

    captured = capsys.readouterr()
    assert exit_code == 2
    payload = json.loads(captured.out)
    assert payload["error"]["code"] == "deal_sheet_invalid"
    assert "bad deal" in payload["error"]["message"]


def test_cli_non_json_error_stays_stderr_only(
    capsys: pytest.CaptureFixture[str],
) -> None:
    exit_code = main(["check", "/no/such/file.pdf"])

    captured = capsys.readouterr()
    assert exit_code == 2
    assert "redline: PDF not found" in captured.err
    assert captured.out == ""


def test_cli_json_success_has_no_error_key(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    report = CheckReport(
        facts_summary={},
        deterministic_findings=[],
        advisory_findings=[],
        could_not_verify=[],
        summary=Summary.from_findings([]),
        exit_code=0,
    )

    def ok(*args: object, **kwargs: object) -> CheckReport:
        return report

    monkeypatch.setattr("redline.cli.check_lease", ok)

    exit_code = main(["check", "x.pdf", "--json"])

    captured = capsys.readouterr()
    assert exit_code == 0
    payload = json.loads(captured.out)
    assert "error" not in payload
    assert "deterministic_findings" in payload
