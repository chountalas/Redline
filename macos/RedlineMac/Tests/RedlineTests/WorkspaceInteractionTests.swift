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

    func testOpeningRunSheetIsIgnoredWhileRunIsActive() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.showSettingsPanel = true
        ws.run = .running(step: 1)

        ws.openRunSheet()

        XCTAssertFalse(ws.showRunSheet)
        XCTAssertFalse(ws.showSettingsPanel)
    }

    func testNavigationIsIgnoredWhileRunIsActive() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.loadExamples()
        let first = ws.documents[0].id
        let second = ws.documents[1].id
        ws.selectDoc(first)
        ws.screen = .workspace
        ws.run = .running(step: 1)

        ws.selectDoc(second)
        ws.goHome()

        XCTAssertEqual(ws.selectedDocID, first)
        XCTAssertEqual(ws.screen, .workspace)
        XCTAssertTrue(ws.run.isRunning)
    }

    func testRetryAfterFailureReopensRunSheetFromCleanPanelState() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.showSettingsPanel = true
        ws.pendingRetry = PendingRunRetry(
            source: RunSource(
                leasePDF: URL(fileURLWithPath: "/tmp/missing.pdf"),
                dealSheet: nil,
                context: "",
                failOn: .error,
                provider: .codex,
                model: "",
                baseURL: "",
                apiKey: ""
            ),
            saveThread: true
        )

        ws.retryAfterFailure()

        XCTAssertTrue(ws.showRunSheet)
        XCTAssertFalse(ws.showSettingsPanel)
        XCTAssertEqual(ws.pendingRetry?.source.leasePDF.path, "/tmp/missing.pdf")
        XCTAssertEqual(ws.pendingRetry?.saveThread, true)
    }

    func testCancelRunSheetRemovesPendingImportedRetrySources() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-cancel-retry-sheet-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let sourceLease = dir.appendingPathComponent("lease.pdf")
        let sourceDeal = dir.appendingPathComponent("deal.yaml")
        try "%PDF-1.4\n".write(to: sourceLease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: sourceDeal, atomically: true, encoding: .utf8)

        let storeURL = dir.appendingPathComponent("library.json")
        let ws = Workspace(storeURL: storeURL)
        let prepared = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: sourceLease, dealSheet: sourceDeal, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )
        ws.showRunSheet = true
        ws.pendingRetry = PendingRunRetry(source: prepared.runtime, saveThread: false)

        ws.cancelRunSheet()

        XCTAssertFalse(ws.showRunSheet)
        XCTAssertNil(ws.pendingRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.runtime.leasePDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.runtime.dealSheet?.path ?? ""))
    }

    func testWorkspaceLaunchSweepsUnreferencedImportedSources() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-launch-import-sweep-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("library.json")

        let savedLease = dir.appendingPathComponent("saved.pdf")
        let savedDeal = dir.appendingPathComponent("saved.yaml")
        let orphanLease = dir.appendingPathComponent("orphan.pdf")
        let orphanDeal = dir.appendingPathComponent("orphan.yaml")
        try "%PDF-1.4\n".write(to: savedLease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: savedDeal, atomically: true, encoding: .utf8)
        try "%PDF-1.4\n".write(to: orphanLease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: orphanDeal, atomically: true, encoding: .utf8)

        let saved = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: savedLease, dealSheet: savedDeal, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )
        let orphan = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: orphanLease, dealSheet: orphanDeal, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )
        var doc = SampleData.documents[0]
        doc.source = saved.persisted
        try LibraryStore.save(
            LibrarySnapshot(
                documents: [doc],
                groups: [DocGroup(id: "yours", label: "Your documents", ids: [doc.id])],
                selectedDocID: doc.id,
                reviewed: [:],
                notes: [:]),
            to: storeURL
        )

        _ = Workspace(storeURL: storeURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.persisted.leasePDF.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.persisted.dealSheet?.path ?? ""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.persisted.leasePDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.persisted.dealSheet?.path ?? ""))
    }

    func testWorkspaceLaunchPreservesImportedSourcesWhenLibraryIsCorrupt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-corrupt-library-import-preserve-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let storeURL = dir.appendingPathComponent("library.json")
        let lease = dir.appendingPathComponent("recoverable.pdf")
        let deal = dir.appendingPathComponent("recoverable.yaml")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: deal, atomically: true, encoding: .utf8)
        let prepared = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: lease, dealSheet: deal, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )
        try "{ not valid json".write(to: storeURL, atomically: true, encoding: .utf8)

        _ = Workspace(storeURL: storeURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.persisted.leasePDF.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.persisted.dealSheet?.path ?? ""))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("library.corrupt-") })
    }

    func testDeleteConfirmationCancelPathDoesNotApproveDeletion() {
        let doc = SampleData.documents[0]
        var capturedMessage = ""
        var capturedInfo = ""

        let shouldDelete = DocumentDeleteConfirmation.shouldDelete(doc: doc) { message, informativeText in
            capturedMessage = message
            capturedInfo = informativeText
            return false
        }

        XCTAssertFalse(shouldDelete)
        XCTAssertTrue(capturedMessage.contains(doc.name))
        XCTAssertTrue(capturedInfo.contains("source PDF"))
    }

    func testDeleteDocumentRemovesLibraryReferencesAndSelectsNextDocument() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.loadExamples()
        let removed = ws.documents[0].id
        let next = ws.documents[1].id
        ws.selectDoc(removed)
        ws.reviewed["\(removed):finding"] = true
        ws.notes["\(removed):finding"] = "note"

        ws.deleteDoc(removed)

        XCTAssertNil(ws.doc(removed))
        XCTAssertEqual(ws.selectedDocID, next)
        XCTAssertFalse(ws.groups.contains { $0.ids.contains(removed) })
        XCTAssertFalse(ws.reviewed.keys.contains { $0.hasPrefix("\(removed):") })
        XCTAssertFalse(ws.notes.keys.contains { $0.hasPrefix("\(removed):") })
    }

    func testDeleteDocumentRemovesUnsharedImportedSources() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-delete-imported-source-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let sourceLease = dir.appendingPathComponent("lease.pdf")
        let sourceDeal = dir.appendingPathComponent("deal.yaml")
        try "%PDF-1.4\n".write(to: sourceLease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: sourceDeal, atomically: true, encoding: .utf8)

        let storeURL = dir.appendingPathComponent("library.json")
        let ws = Workspace(storeURL: storeURL)
        let prepared = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: sourceLease, dealSheet: sourceDeal, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )

        var doc = SampleData.documents[0]
        doc.source = prepared.persisted
        ws.documents = [doc]
        ws.groups = [DocGroup(id: "yours", label: "Your documents", ids: [doc.id])]
        ws.selectedDocID = doc.id

        ws.deleteDoc(doc.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.persisted.leasePDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.persisted.dealSheet?.path ?? ""))
    }

    func testDeleteDocumentKeepsImportedSourcesStillReferencedByAnotherDocument() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-delete-shared-imported-source-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let sourceLease = dir.appendingPathComponent("lease.pdf")
        try "%PDF-1.4\n".write(to: sourceLease, atomically: true, encoding: .utf8)
        let storeURL = dir.appendingPathComponent("library.json")
        let ws = Workspace(storeURL: storeURL)
        let prepared = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: sourceLease, dealSheet: nil, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )

        var first = SampleData.documents[0]
        var second = SampleData.documents[1]
        first.source = prepared.persisted
        second.source = prepared.persisted
        ws.documents = [first, second]
        ws.groups = [DocGroup(id: "yours", label: "Your documents", ids: [first.id, second.id])]
        ws.selectedDocID = first.id

        ws.deleteDoc(first.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.persisted.leasePDF.path))
        XCTAssertEqual(ws.doc(second.id)?.source?.leasePDF, prepared.persisted.leasePDF)
    }

    func testRenameDocumentIgnoresBlankNames() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.loadExamples()
        let id = ws.documents[0].id
        let originalName = ws.documents[0].name

        ws.renameDoc(id, to: "   ")
        XCTAssertEqual(ws.doc(id)?.name, originalName)

        ws.renameDoc(id, to: "Updated lease")
        XCTAssertEqual(ws.doc(id)?.name, "Updated lease")
    }

    func testReplaceSourcePDFImportsNewFileAndUpdatesDocumentName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-replace-source-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("library.json")

        let original = dir.appendingPathComponent("old.pdf")
        let replacement = dir.appendingPathComponent("new lease.pdf")
        try "%PDF-1.4\n".write(to: original, atomically: true, encoding: .utf8)
        try "%PDF-1.4\n".write(to: replacement, atomically: true, encoding: .utf8)

        let ws = Workspace(storeURL: storeURL)
        var doc = SampleData.documents[0]
        doc.source = RunSource(
            leasePDF: original, dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "", baseURL: "",
            apiKey: "", thread: "")
        ws.documents = [doc]
        ws.groups = [DocGroup(id: "yours", label: "Your documents", ids: [doc.id])]
        ws.selectedDocID = doc.id

        try ws.replaceSourcePDF(for: doc.id, with: replacement)

        let updated = try XCTUnwrap(ws.doc(doc.id))
        XCTAssertEqual(updated.name, "new lease")
        XCTAssertEqual(updated.source?.originalLeaseFilename, "new lease.pdf")
        XCTAssertNotEqual(updated.source?.leasePDF, replacement)
        XCTAssertEqual(updated.source?.leasePDF.deletingLastPathComponent().lastPathComponent, "Imported Sources")
        XCTAssertTrue(FileManager.default.fileExists(atPath: updated.source?.leasePDF.path ?? ""))
    }

    func testReplaceSourcePDFRemovesUnsharedOldImportedLease() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-replace-cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("library.json")

        let original = dir.appendingPathComponent("old.pdf")
        let replacement = dir.appendingPathComponent("new.pdf")
        try "%PDF-1.4\n".write(to: original, atomically: true, encoding: .utf8)
        try "%PDF-1.4\n".write(to: replacement, atomically: true, encoding: .utf8)

        let ws = Workspace(storeURL: storeURL)
        let prepared = try RunSourceFileStore.prepare(
            RunSource(
                leasePDF: original, dealSheet: nil, context: "",
                failOn: .error, provider: .codex, model: "", baseURL: "",
                apiKey: "", thread: ""),
            storeURL: storeURL,
            persistThread: false
        )
        var doc = SampleData.documents[0]
        doc.source = prepared.persisted
        ws.documents = [doc]
        ws.groups = [DocGroup(id: "yours", label: "Your documents", ids: [doc.id])]
        ws.selectedDocID = doc.id

        try ws.replaceSourcePDF(for: doc.id, with: replacement)

        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.persisted.leasePDF.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ws.doc(doc.id)?.source?.leasePDF.path ?? ""))
    }

    func testAllErrorsClearedUsesTheProvidedDocumentID() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        let doc = SampleData.pembina
        let selected = SampleData.idylwyld
        let error = doc.findings.first { $0.severity == .error }!
        ws.documents = [doc, selected]
        ws.selectedDocID = selected.id
        ws.reviewed["\(doc.id):\(error.id)"] = true

        XCTAssertTrue(ws.allErrorsCleared(doc))
    }
}
