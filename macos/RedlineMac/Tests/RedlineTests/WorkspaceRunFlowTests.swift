import XCTest
@testable import Redline

@MainActor
final class WorkspaceRunFlowTests: XCTestCase {
    private final class CapturingRunner: RedlineRunning {
        var leasePDF: URL?
        var profile: ReviewProfile?
        var dealSheet: URL?
        var context: String?
        var thread: String?
        var provider: LLMProvider?
        var model: String?
        var baseURL: String?
        var apiKey: String?
        var callCount = 0
        let report: CheckReport

        init(report: CheckReport) {
            self.report = report
        }

        func run(
            leasePDF: URL,
            profile: ReviewProfile,
            dealSheet: URL?,
            context: String,
            failOn: FailOn,
            provider: LLMProvider,
            model: String,
            baseURL: String,
            apiKey: String,
            thread: String,
            onLaunch: @Sendable (Process) -> Void
        ) async throws -> CheckReport {
            callCount += 1
            self.leasePDF = leasePDF
            self.profile = profile
            self.dealSheet = dealSheet
            self.context = context
            self.thread = thread
            self.provider = provider
            self.model = model
            self.baseURL = baseURL
            self.apiKey = apiKey
            return report
        }
    }

    private final class FailingRunner: RedlineRunning {
        var leasePDF: URL?
        var dealSheet: URL?

        func run(
            leasePDF: URL,
            profile: ReviewProfile,
            dealSheet: URL?,
            context: String,
            failOn: FailOn,
            provider: LLMProvider,
            model: String,
            baseURL: String,
            apiKey: String,
            thread: String,
            onLaunch: @Sendable (Process) -> Void
        ) async throws -> CheckReport {
            self.leasePDF = leasePDF
            self.dealSheet = dealSheet
            throw RedlineRunError.processFailed("engine failed")
        }
    }

    private actor AsyncGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func open() {
            guard !isOpen else { return }
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private actor PrepareCoordinator {
        private let firstStarted = AsyncGate()
        private let releaseFirst = AsyncGate()
        private var calls = 0

        func prepare(source: RunSource, storeURL: URL, persistThread: Bool) async throws -> PreparedRunSource {
            calls += 1
            if calls == 1 {
                await firstStarted.open()
                await releaseFirst.wait()
            }
            return try RunSourceFileStore.prepare(source, storeURL: storeURL, persistThread: persistThread)
        }

        func waitForFirstStart() async {
            await firstStarted.wait()
        }

        func releaseFirst() async {
            await releaseFirst.open()
        }
    }

    private final class HoldingRunner: RedlineRunning {
        var leasePDF: URL?
        let report: CheckReport
        private let releaseGate = AsyncGate()

        init(report: CheckReport) {
            self.report = report
        }

        func run(
            leasePDF: URL,
            profile: ReviewProfile,
            dealSheet: URL?,
            context: String,
            failOn: FailOn,
            provider: LLMProvider,
            model: String,
            baseURL: String,
            apiKey: String,
            thread: String,
            onLaunch: @Sendable (Process) -> Void
        ) async throws -> CheckReport {
            self.leasePDF = leasePDF
            await releaseGate.wait()
            return report
        }

        func release() async {
            await releaseGate.open()
        }
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-workspace-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func report() throws -> CheckReport {
        let json = """
        {
          "facts_summary": {"source_file":"lease.pdf","page_count":1},
          "deterministic_findings": [],
          "advisory_findings": [],
          "could_not_verify": [],
          "deal_terms": [],
          "summary": {"error":0,"warn":0,"info":0,"could_not_verify":0,"advisory":0},
          "exit_code": 0
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(CheckReport.self, from: json)
    }

    private func waitForDocument(_ ws: Workspace) async throws {
        for _ in 0..<80 {
            if !ws.documents.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for run result")
    }

    private func waitForIdleRun(_ ws: Workspace) async throws {
        for _ in 0..<120 {
            if !ws.run.isRunning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for run to finish")
    }

    private func waitForRunnerCall(_ runner: CapturingRunner) async throws {
        for _ in 0..<120 {
            if runner.leasePDF != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for runner call")
    }

    private func waitForHoldingRunnerCall(_ runner: HoldingRunner) async throws {
        for _ in 0..<120 {
            if runner.leasePDF != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for runner call")
    }

    private func waitForFailure(_ ws: Workspace) async throws {
        for _ in 0..<120 {
            if ws.run.failure != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for run failure")
    }

    func testStartRunImportsSourcesAndDoesNotPersistThreadByDefault() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("source.pdf")
        let deal = dir.appendingPathComponent("deal.yaml")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: deal, atomically: true, encoding: .utf8)

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)

        ws.startRun(
            leasePDF: lease,
            deal: DealContext(thread: "private thread", dealSheet: deal, context: "focus", saveThread: false)
        )
        try await waitForDocument(ws)
        try await waitForIdleRun(ws)

        let runLease = try XCTUnwrap(runner.leasePDF)
        let runDeal = try XCTUnwrap(runner.dealSheet)
        XCTAssertNotEqual(runLease, lease)
        XCTAssertNotEqual(runDeal, deal)
        XCTAssertEqual(runLease.deletingLastPathComponent().lastPathComponent, "Imported Sources")
        XCTAssertEqual(runDeal.deletingLastPathComponent().lastPathComponent, "Imported Sources")
        XCTAssertEqual(runner.thread, "private thread")
        XCTAssertEqual(runner.context, "Focus note:\nfocus\n\nReview context:\nprivate thread")
        XCTAssertEqual(runner.profile, .leaseGeneral)
        XCTAssertEqual(ws.documents.first?.source?.thread, "")
        XCTAssertEqual(ws.documents.first?.source?.context, "focus")
        XCTAssertEqual(ws.documents.first?.source?.profile, .leaseGeneral)
        XCTAssertEqual(ws.documents.first?.source?.reviewContextState, .unsaved)
    }

    func testUnsavedReviewContextFeedsRunButBlocksSilentRecheck() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("source.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)

        ws.startRun(
            leasePDF: lease,
            deal: DealContext(thread: "Cannot accept auto-renewal.", dealSheet: nil, context: "", saveThread: false)
        )
        try await waitForDocument(ws)
        try await waitForIdleRun(ws)

        XCTAssertEqual(runner.context, "Review context:\nCannot accept auto-renewal.")
        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(ws.documents.first?.source?.thread, "")
        XCTAssertEqual(ws.documents.first?.source?.reviewContextState, .unsaved)

        ws.recheck()

        XCTAssertEqual(runner.callCount, 1, "re-check must not silently drop unsaved review context")
        XCTAssertTrue(ws.showRunSheet)
        XCTAssertEqual(ws.pendingRetry?.source.reviewContextState, .unsaved)
    }

    func testRecheckUsesCurrentAISettings() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("source.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)

        ws.startRun(
            leasePDF: lease,
            deal: DealContext(thread: "", dealSheet: nil, context: "", saveThread: false)
        )
        try await waitForDocument(ws)
        try await waitForIdleRun(ws)
        XCTAssertEqual(runner.callCount, 1)

        ws.provider = .openai
        ws.profile = .leaseMath
        ws.model = "gpt-test"
        ws.baseURL = "https://api.example"
        ws.apiKey = "sk-live"
        ws.recheck()

        for _ in 0..<120 {
            if runner.callCount == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(runner.callCount, 2)
        XCTAssertEqual(runner.profile, .leaseMath)
        XCTAssertEqual(runner.provider, .openai)
        XCTAssertEqual(runner.model, "gpt-test")
        XCTAssertEqual(runner.baseURL, "https://api.example")
        XCTAssertEqual(runner.apiKey, "sk-live")
    }

    func testStartRunRemovesDroppedTemporaryLeaseAfterImport() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let representation = dir.appendingPathComponent("drop-representation.pdf")
        try "%PDF-1.4\n".write(to: representation, atomically: true, encoding: .utf8)
        let droppedLease = try RunSheetFileIntake.copyDroppedPDFToTemporaryURL(
            representation,
            suggestedName: "Dropped Lease.pdf"
        )

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)

        ws.startRun(
            leasePDF: droppedLease,
            deal: DealContext(thread: "", dealSheet: nil, context: "", saveThread: false),
            originalLeaseFilename: droppedLease.lastPathComponent
        )
        try await waitForDocument(ws)

        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedLease.deletingLastPathComponent().path))
        XCTAssertEqual(runner.leasePDF?.deletingLastPathComponent().lastPathComponent, "Imported Sources")
        XCTAssertEqual(ws.documents.first?.source?.originalLeaseFilename, "Dropped Lease.pdf")
    }

    func testCancelledImportCannotClearNewRunState() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let firstRepresentation = dir.appendingPathComponent("first-drop-representation.pdf")
        let secondLease = dir.appendingPathComponent("second.pdf")
        try "%PDF-1.4\n".write(to: firstRepresentation, atomically: true, encoding: .utf8)
        try "%PDF-1.4\n".write(to: secondLease, atomically: true, encoding: .utf8)
        let firstLease = try RunSheetFileIntake.copyDroppedPDFToTemporaryURL(
            firstRepresentation,
            suggestedName: "First dropped.pdf"
        )

        let coordinator = PrepareCoordinator()
        let runner = try HoldingRunner(report: report())
        let ws = Workspace(
            storeURL: dir.appendingPathComponent("library.json"),
            runner: runner,
            prepareRunSource: { source, storeURL, persistThread in
                try await coordinator.prepare(source: source, storeURL: storeURL, persistThread: persistThread)
            }
        )

        ws.startRun(
            leasePDF: firstLease,
            deal: DealContext(thread: "", dealSheet: nil, context: "", saveThread: false)
        )
        await coordinator.waitForFirstStart()
        ws.cancelRun()

        ws.startRun(
            leasePDF: secondLease,
            deal: DealContext(thread: "", dealSheet: nil, context: "", saveThread: false)
        )
        try await waitForHoldingRunnerCall(runner)
        XCTAssertTrue(ws.run.isRunning)

        await coordinator.releaseFirst()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(ws.run.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstLease.deletingLastPathComponent().path))
        XCTAssertEqual(runner.leasePDF?.deletingLastPathComponent().lastPathComponent, "Imported Sources")

        await runner.release()
        try await waitForDocument(ws)
        XCTAssertEqual(ws.documents.first?.source?.originalLeaseFilename, "second.pdf")
    }

    func testStartRunPersistsThreadWhenUserOptsIn() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("source.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)

        ws.startRun(
            leasePDF: lease,
            deal: DealContext(thread: "save this thread", dealSheet: nil, context: "", saveThread: true)
        )
        try await waitForDocument(ws)

        XCTAssertEqual(runner.thread, "save this thread")
        XCTAssertEqual(ws.documents.first?.source?.thread, "save this thread")
    }

    func testFailedRunRetryPreservesSaveThreadChoice() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("source.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)
        ws.provider = .openai
        ws.model = "gpt-test"
        ws.apiKey = ""

        ws.startRun(
            leasePDF: lease,
            deal: DealContext(thread: "save on retry", dealSheet: nil, context: "", saveThread: true)
        )

        XCTAssertEqual(ws.pendingRetry?.source.thread, "save on retry")
        XCTAssertEqual(ws.pendingRetry?.saveThread, true)
    }

    func testDismissFailedPreflightRemovesDroppedTemporaryRetryLease() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let representation = dir.appendingPathComponent("drop-representation.pdf")
        try "%PDF-1.4\n".write(to: representation, atomically: true, encoding: .utf8)
        let droppedLease = try RunSheetFileIntake.copyDroppedPDFToTemporaryURL(
            representation,
            suggestedName: "Dropped Lease.pdf"
        )

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)
        ws.provider = .openai
        ws.model = "gpt-test"
        ws.apiKey = ""

        ws.startRun(
            leasePDF: droppedLease,
            deal: DealContext(thread: "", dealSheet: nil, context: "", saveThread: false),
            originalLeaseFilename: droppedLease.lastPathComponent
        )

        XCTAssertNotNil(ws.pendingRetry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: droppedLease.path))

        ws.dismissFailure()

        XCTAssertNil(ws.pendingRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: droppedLease.deletingLastPathComponent().path))
    }

    func testRecheckPreservesRenamedDocumentName() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("source.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)

        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)
        var doc = SampleData.documents[0]
        doc.name = "Custom Deal Name"
        doc.source = RunSource(
            leasePDF: lease, dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "", baseURL: "",
            apiKey: "", thread: "")
        ws.documents = [doc]
        ws.groups = [DocGroup(id: "yours", label: "Your documents", ids: [doc.id])]
        ws.selectedDocID = doc.id

        ws.recheck()
        try await waitForRunnerCall(runner)
        try await waitForIdleRun(ws)

        XCTAssertEqual(ws.doc(doc.id)?.name, "Custom Deal Name")
        XCTAssertEqual(runner.leasePDF?.deletingLastPathComponent().lastPathComponent, "Imported Sources")
    }

    func testStartRunFromImportedRetryPreservesOriginalLeaseName() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("original lease.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        let storeURL = dir.appendingPathComponent("library.json")
        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: storeURL, runner: runner)
        let prepared = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: lease, dealSheet: nil, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )

        ws.startRun(
            leasePDF: prepared.runtime.leasePDF,
            deal: DealContext(thread: "", dealSheet: nil, context: "", saveThread: false),
            originalLeaseFilename: prepared.runtime.originalLeaseFilename
        )
        try await waitForDocument(ws)

        XCTAssertEqual(ws.documents.first?.name, "original lease")
        XCTAssertEqual(runner.leasePDF, prepared.runtime.leasePDF)
    }

    func testDismissFailedRunRemovesUnownedImportedRetrySources() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lease = dir.appendingPathComponent("source.pdf")
        let deal = dir.appendingPathComponent("deal.yaml")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: deal, atomically: true, encoding: .utf8)

        let runner = FailingRunner()
        let ws = Workspace(storeURL: dir.appendingPathComponent("library.json"), runner: runner)
        ws.startRun(
            leasePDF: lease,
            deal: DealContext(thread: "", dealSheet: deal, context: "", saveThread: false)
        )
        try await waitForFailure(ws)

        let retrySource = try XCTUnwrap(ws.pendingRetry?.source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retrySource.leasePDF.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retrySource.dealSheet?.path ?? ""))

        ws.dismissFailure()

        XCTAssertNil(ws.pendingRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retrySource.leasePDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: retrySource.dealSheet?.path ?? ""))
    }

    func testStartingRetryWithNewInputsRemovesAbandonedImportedSources() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldLease = dir.appendingPathComponent("old.pdf")
        let oldDeal = dir.appendingPathComponent("old.yaml")
        let newLease = dir.appendingPathComponent("new.pdf")
        try "%PDF-1.4\n".write(to: oldLease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: oldDeal, atomically: true, encoding: .utf8)
        try "%PDF-1.4\n".write(to: newLease, atomically: true, encoding: .utf8)

        let storeURL = dir.appendingPathComponent("library.json")
        let runner = try CapturingRunner(report: report())
        let ws = Workspace(storeURL: storeURL, runner: runner)
        let abandoned = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: oldLease, dealSheet: oldDeal, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )
        ws.pendingRetry = PendingRunRetry(source: abandoned.runtime, saveThread: false)

        ws.startRun(
            leasePDF: newLease,
            deal: DealContext(thread: "", dealSheet: nil, context: "", saveThread: false)
        )
        try await waitForDocument(ws)

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.runtime.leasePDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.runtime.dealSheet?.path ?? ""))
        XCTAssertEqual(runner.leasePDF?.deletingLastPathComponent().lastPathComponent, "Imported Sources")
        XCTAssertTrue(FileManager.default.fileExists(atPath: runner.leasePDF?.path ?? ""))
    }
}
