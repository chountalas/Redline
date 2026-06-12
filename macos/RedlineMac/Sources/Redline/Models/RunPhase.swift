import Foundation

/// One source of truth for an engine run. Replaces the ad-hoc checking/isRunning/runError trio.
enum RunPhase: Equatable {
    case idle
    case running(step: Int)
    case failed(RunFailure)

    var isRunning: Bool { if case .running = self { return true } else { return false } }
    var step: Int { if case .running(let s) = self { return s } else { return 0 } }
    var failure: RunFailure? { if case .failed(let f) = self { return f } else { return nil } }
}

/// A run failure mapped to a plain-language cause + guidance. The raw message is preserved
/// for the disclosure in the error UI (G8).
struct RunFailure: Equatable {
    enum Cause: Equatable { case scannedPDF, badInput, toolingMissing, auth, badOutput, unknown }
    let cause: Cause
    let guidance: String
    let raw: String

    static func map(_ error: Error) -> RunFailure {
        let raw = (error as? RedlineRunError)?.errorDescription ?? error.localizedDescription
        // Typed engine codes (Phase 2 envelope) are authoritative — map them before the
        // string heuristics, which only exist for non-enveloped failures (e.g. provider tracebacks).
        if let re = error as? RedlineRunError, case .engine(let code, _) = re {
            return mapEngineCode(code, raw: raw)
        }
        let low = raw.lowercased()
        let cause: Cause
        // String checks precede case checks: scanned-PDF and auth failures both arrive wrapped
        // as .processFailed, so their messages must be inspected before the case-based fallbacks.
        if low.contains("no extractable text") || low.contains("scanned") { cause = .scannedPDF }
        else if low.contains("could not import") { cause = .badInput }
        else if error is RedlineRunError, case .processLaunchFailed = (error as! RedlineRunError) { cause = .toolingMissing }
        else if low.contains("api key") || low.contains("unauthorized") || low.contains("401") { cause = .auth }
        else if error is RedlineRunError, case .invalidJSON = (error as! RedlineRunError) { cause = .badOutput }
        else { cause = .unknown }
        return RunFailure(cause: cause, guidance: cause.guidance, raw: raw)
    }

    private static func mapEngineCode(_ code: String, raw: String) -> RunFailure {
        let cause: Cause
        let guidance: String
        switch code {
        case "scanned_pdf":
            cause = .scannedPDF
            guidance = Cause.scannedPDF.guidance
        case "pdf_not_found":
            cause = .badInput
            guidance = "Couldn't find that PDF — it may have been moved or deleted. Re-add the file."
        case "pdf_unreadable":
            cause = .badInput
            guidance = "Couldn't open that PDF — it may be corrupted or password-protected. Try another copy."
        case "extraction_failed":
            cause = .badInput
            guidance = "Couldn't pull text from that PDF. Try re-exporting it, or use an OCR'd copy."
        case "deal_sheet_invalid":
            cause = .badInput
            guidance = "The comparison sheet couldn't be read — check its formatting and try again."
        default:
            cause = .unknown
            guidance = Cause.unknown.guidance
        }
        return RunFailure(cause: cause, guidance: guidance, raw: raw)
    }
}

private extension RunFailure.Cause {
    var guidance: String {
        switch self {
        case .scannedPDF: "This PDF is a scan — Redline needs selectable text. Try an OCR'd copy."
        case .badInput: "Redline couldn't read that input. Check the file (and comparison sheet, if any) and try again."
        case .toolingMissing: "Couldn't launch the checker. Confirm `uv` is installed and you're signed into your provider."
        case .auth: "The provider rejected the request. Check your API key in Settings."
        case .badOutput: "The checker returned unexpected output. Re-run, or switch providers in Settings."
        case .unknown: "The check failed. See details below or re-run."
        }
    }
}
