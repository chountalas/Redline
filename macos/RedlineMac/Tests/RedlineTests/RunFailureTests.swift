import XCTest
@testable import Redline

final class RunFailureTests: XCTestCase {
    // MARK: string-fallback path (non-enveloped failures — provider tracebacks etc.)

    func testScannedPdfMapsToScannedCause() {
        let f = RunFailure.map(RedlineRunError.processFailed("redline: This PDF has no extractable text and looks scanned; OCR is unsupported in v1."))
        XCTAssertEqual(f.cause, .scannedPDF)
    }
    func testLaunchFailureMapsToToolingMissing() {
        let f = RunFailure.map(RedlineRunError.processLaunchFailed("No such file or directory"))
        XCTAssertEqual(f.cause, .toolingMissing)
    }
    func testUnknownStaysGeneric() {
        let f = RunFailure.map(RedlineRunError.processFailed("kaboom"))
        XCTAssertEqual(f.cause, .unknown)
        XCTAssertEqual(f.raw, "kaboom")
    }
    func testAuthErrorMapsToAuth() {
        XCTAssertEqual(RunFailure.map(RedlineRunError.processFailed("Error 401 unauthorized: invalid api key")).cause, .auth)
    }
    func testInvalidJSONMapsToBadOutput() {
        XCTAssertEqual(RunFailure.map(RedlineRunError.invalidJSON("Redline returned non-JSON output.")).cause, .badOutput)
    }
    func testCancelledErrorDescription() {
        XCTAssertEqual(RedlineRunError.cancelled.errorDescription, "Check cancelled.")
    }

    // MARK: Step 3.3 — typed engine error contract (G7-UI / G8)

    // 1. RedlineRunner.engineError(from:) decoder

    func testEngineErrorDecodesEnvelope() {
        let data = Data(#"{"error":{"code":"scanned_pdf","message":"x"}}"#.utf8)
        XCTAssertEqual(RedlineRunner.engineError(from: data),
                       RedlineRunError.engine(code: "scanned_pdf", message: "x"))
    }
    func testEngineErrorReturnsNilForEmptyObject() {
        XCTAssertNil(RedlineRunner.engineError(from: Data("{}".utf8)))
    }
    func testEngineErrorReturnsNilForFakeReport() {
        // A non-envelope JSON object (shaped vaguely like a report) is not an error envelope.
        let data = Data(#"{"verdict":"pass","findings":[]}"#.utf8)
        XCTAssertNil(RedlineRunner.engineError(from: data))
    }

    // 2. RunFailure.map(.engine(...)) — cause + guidance + raw for EACH code

    func testEngineScannedPdfMapsToScannedCause() {
        let f = RunFailure.map(RedlineRunError.engine(code: "scanned_pdf", message: "scanned msg"))
        XCTAssertEqual(f.cause, .scannedPDF)
        XCTAssertEqual(f.guidance, "This PDF is a scan — Redline needs selectable text. Try an OCR'd copy.")
        XCTAssertEqual(f.raw, "scanned msg")
    }
    func testEnginePdfNotFoundMapsToBadInput() {
        let f = RunFailure.map(RedlineRunError.engine(code: "pdf_not_found", message: "missing"))
        XCTAssertEqual(f.cause, .badInput)
        XCTAssertEqual(f.guidance, "Couldn't find that PDF — it may have been moved or deleted. Re-add the file.")
        XCTAssertEqual(f.raw, "missing")
    }
    func testEnginePdfUnreadableMapsToBadInput() {
        let f = RunFailure.map(RedlineRunError.engine(code: "pdf_unreadable", message: "corrupt"))
        XCTAssertEqual(f.cause, .badInput)
        XCTAssertEqual(f.guidance, "Couldn't open that PDF — it may be corrupted or password-protected. Try another copy.")
        XCTAssertEqual(f.raw, "corrupt")
    }
    func testEngineExtractionFailedMapsToBadInput() {
        let f = RunFailure.map(RedlineRunError.engine(code: "extraction_failed", message: "no text"))
        XCTAssertEqual(f.cause, .badInput)
        XCTAssertEqual(f.guidance, "Couldn't pull text from that PDF. Try re-exporting it, or use an OCR'd copy.")
        XCTAssertEqual(f.raw, "no text")
    }
    func testEngineDealSheetInvalidMapsToBadInput() {
        let f = RunFailure.map(RedlineRunError.engine(code: "deal_sheet_invalid", message: "bad yaml"))
        XCTAssertEqual(f.cause, .badInput)
        XCTAssertEqual(f.guidance, "The comparison sheet couldn't be read — check its formatting and try again.")
        XCTAssertEqual(f.raw, "bad yaml")
    }
    func testEngineUnknownCodeMapsToUnknown() {
        let f = RunFailure.map(RedlineRunError.engine(code: "weird", message: "huh"))
        XCTAssertEqual(f.cause, .unknown)
        XCTAssertEqual(f.guidance, "The check failed. See details below or re-run.")
        XCTAssertEqual(f.raw, "huh")
    }

    // 3. Regression: the string-fallback auth path is preserved for non-enveloped failures.

    func testProcessFailedAuthStillMapsToAuth() {
        let f = RunFailure.map(RedlineRunError.processFailed("Traceback ... 401 unauthorized ..."))
        XCTAssertEqual(f.cause, .auth)
    }
}
