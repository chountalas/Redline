import XCTest
@testable import Redline

@MainActor
final class WorkspaceInteractionTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-workspace-interactions-\(UUID().uuidString).json")
    }

    func testOpeningRunSheetClosesSettingsPanel() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.showSettingsPanel = true

        ws.openRunSheet()

        XCTAssertTrue(ws.showRunSheet)
        XCTAssertFalse(ws.showSettingsPanel)
    }

    func testRetryAfterFailureReopensRunSheetFromCleanPanelState() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.showSettingsPanel = true
        ws.pendingRetry = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/missing.pdf"),
            dealSheet: nil,
            context: "",
            failOn: .error,
            provider: .codex,
            model: "",
            baseURL: "",
            apiKey: ""
        )

        ws.retryAfterFailure()

        XCTAssertTrue(ws.showRunSheet)
        XCTAssertFalse(ws.showSettingsPanel)
        XCTAssertEqual(ws.pendingRetry?.leasePDF.path, "/tmp/missing.pdf")
    }
}
