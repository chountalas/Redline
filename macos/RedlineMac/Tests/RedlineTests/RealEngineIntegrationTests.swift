import XCTest
@testable import Redline

final class RealEngineIntegrationTests: XCTestCase {
    func testSwiftRunnerCompletesRealLeaseWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["REDLINE_REAL_ENGINE_TESTS"] == "1" else {
            throw XCTSkip("Set REDLINE_REAL_ENGINE_TESTS=1 to run the real Codex-backed engine smoke test.")
        }

        guard let leasePath = ProcessInfo.processInfo.environment["REDLINE_REAL_LEASE_PDF"],
              !leasePath.isEmpty else {
            throw XCTSkip("Set REDLINE_REAL_LEASE_PDF to an uncommitted local PDF.")
        }
        let leaseURL = URL(fileURLWithPath: leasePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: leaseURL.path), "real smoke lease must exist")

        let runner = RedlineRunner(repoRoot: repoRoot())
        let report = try await runner.run(
            leasePDF: leaseURL,
            dealSheet: nil,
            context: "",
            failOn: .error,
            provider: .codex,
            model: "",
            baseURL: "",
            apiKey: "",
            onLaunch: { _ in }
        )

        XCTAssertEqual(report.exitCode, 0)
        XCTAssertFalse(report.deterministicFindings.isEmpty)
        XCTAssertEqual(report.factsSummary?.pageCount, 9)

        let source = RunSource(
            leasePDF: leaseURL,
            dealSheet: nil,
            context: "",
            failOn: .error,
            provider: .codex,
            model: "",
            baseURL: "",
            apiKey: ""
        )
        let doc = ReportAdapter.makeDoc(from: report, source: source, id: "real-smoke")
        XCTAssertEqual(doc.id, "real-smoke")
        XCTAssertEqual(doc.source?.leasePDF, leaseURL)
        XCTAssertFalse(doc.findings.isEmpty)
        XCTAssertFalse(doc.document.isEmpty)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RedlineTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RedlineMac
            .deletingLastPathComponent() // macos
    }
}
