import UniformTypeIdentifiers
import XCTest
@testable import Redline

final class RunSheetFileIntakeTests: XCTestCase {
    private final class ThreadProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedValue: Bool?

        var recordedMainThreadValue: Bool? {
            lock.withLock { recordedValue }
        }

        func recordCurrentThread() {
            lock.withLock { recordedValue = Thread.isMainThread }
        }
    }

    func testLeaseDropAcceptsFinderFileURLsAndPDFItems() {
        XCTAssertTrue(RunSheetFileIntake.leaseDropTypes.contains(.fileURL))
        XCTAssertTrue(RunSheetFileIntake.leaseDropTypes.contains(.pdf))
    }

    func testPDFValidationIsCaseInsensitive() {
        let url = URL(fileURLWithPath: "/tmp/Lease.PDF")

        XCTAssertTrue(RunSheetFileIntake.isPDF(url))
    }

    func testPDFValidationRejectsOtherFiles() {
        let url = URL(fileURLWithPath: "/tmp/lease.txt")

        XCTAssertFalse(RunSheetFileIntake.isPDF(url))
    }

    func testDealSheetValidationAcceptsOnlyYAMLFiles() {
        XCTAssertTrue(RunSheetFileIntake.isDealSheet(URL(fileURLWithPath: "/tmp/deal.yaml")))
        XCTAssertTrue(RunSheetFileIntake.isDealSheet(URL(fileURLWithPath: "/tmp/deal.yml")))
        XCTAssertTrue(RunSheetFileIntake.isDealSheet(URL(fileURLWithPath: "/tmp/DEAL.YAML")))

        XCTAssertFalse(RunSheetFileIntake.isDealSheet(URL(fileURLWithPath: "/tmp/deal.pdf")))
        XCTAssertFalse(RunSheetFileIntake.isDealSheet(URL(fileURLWithPath: "/tmp/deal.txt")))
    }

    func testDroppedPDFFilenameUsesSuggestedName() {
        let representationURL = URL(fileURLWithPath: "/tmp/NSIRD_RedlineDrop.pdf")

        let filename = RunSheetFileIntake.droppedPDFFilename(
            from: representationURL,
            suggestedName: "Airport Storage Lease.PDF")

        XCTAssertEqual(filename, "Airport Storage Lease.PDF")
    }

    func testDroppedPDFFilenameAddsPDFExtensionToSuggestedName() {
        let representationURL = URL(fileURLWithPath: "/tmp/NSIRD_RedlineDrop.pdf")

        let filename = RunSheetFileIntake.droppedPDFFilename(
            from: representationURL,
            suggestedName: "Airport Storage Lease")

        XCTAssertEqual(filename, "Airport Storage Lease.pdf")
    }

    func testCopyDroppedPDFPreservesSuggestedFilenameInUniqueTemporaryDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-drop-copy-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let representation = root.appendingPathComponent("provider-representation.pdf")
        try "%PDF-1.4\n".write(to: representation, atomically: true, encoding: .utf8)

        let copy = try RunSheetFileIntake.copyDroppedPDFToTemporaryURL(
            representation,
            suggestedName: "Airport Storage Lease.pdf")

        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        XCTAssertEqual(copy.lastPathComponent, "Airport Storage Lease.pdf")
        XCTAssertTrue(copy.deletingLastPathComponent().lastPathComponent.hasPrefix("redline-dropped-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }

    func testTemporaryDroppedPDFCleanupRemovesOwnedDirectoryOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-drop-cleanup-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let representation = root.appendingPathComponent("provider-representation.pdf")
        let userFile = root.appendingPathComponent("user.pdf")
        try "%PDF-1.4\n".write(to: representation, atomically: true, encoding: .utf8)
        try "%PDF-1.4\n".write(to: userFile, atomically: true, encoding: .utf8)

        let copy = try RunSheetFileIntake.copyDroppedPDFToTemporaryURL(representation, suggestedName: "Lease.pdf")

        XCTAssertTrue(RunSheetFileIntake.isTemporaryDroppedPDF(copy))
        XCTAssertFalse(RunSheetFileIntake.isTemporaryDroppedPDF(userFile))

        RunSheetFileIntake.removeTemporaryDroppedPDF(copy)
        RunSheetFileIntake.removeTemporaryDroppedPDF(userFile)

        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    }

    func testDisplayFilenameUsesOriginalNameForImportedRetrySource() {
        let imported = URL(fileURLWithPath: "/tmp/Imported Sources/1234-source.pdf")

        let filename = RunSheetFileIntake.displayFilename(
            for: imported,
            originalFilename: "Airport Storage Lease.pdf")

        XCTAssertEqual(filename, "Airport Storage Lease.pdf")
    }

    func testSourceFileStoreCopiesInputsNextToLibraryStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-import-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let lease = root.appendingPathComponent("original lease.pdf")
        let deal = root.appendingPathComponent("terms.yaml")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        try "total_rent: CAD 600000\n".write(to: deal, atomically: true, encoding: .utf8)

        let storeURL = root.appendingPathComponent("Redline").appendingPathComponent("library.json")
        let source = RunSource(
            leasePDF: lease, dealSheet: deal, context: "ctx",
            failOn: .error, provider: .codex, model: "", baseURL: "",
            apiKey: "secret", thread: "thread")

        let prepared = try RunSourceFileStore.prepare(source, storeURL: storeURL, persistThread: false)

        XCTAssertNotEqual(prepared.runtime.leasePDF, lease)
        XCTAssertNotEqual(prepared.runtime.dealSheet, deal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.runtime.leasePDF.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.runtime.dealSheet?.path ?? ""))
        XCTAssertEqual(prepared.runtime.leasePDF.deletingLastPathComponent().lastPathComponent, "Imported Sources")
        XCTAssertEqual(prepared.runtime.originalLeaseFilename, "original lease.pdf")
        XCTAssertEqual(prepared.persisted.originalLeaseFilename, "original lease.pdf")
        XCTAssertEqual(prepared.runtime.thread, "thread")
        XCTAssertEqual(prepared.persisted.thread, "")
        XCTAssertEqual(prepared.persisted.apiKey, "")
    }

    func testSourceFileStorePrepareInBackgroundCopiesOffMainThread() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-import-background-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let lease = root.appendingPathComponent("original lease.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        let storeURL = root.appendingPathComponent("Redline").appendingPathComponent("library.json")
        let source = RunSource(
            leasePDF: lease, dealSheet: nil, context: "ctx",
            failOn: .error, provider: .codex, model: "", baseURL: "",
            apiKey: "secret", thread: "thread")
        let probe = ThreadProbe()

        let prepared = try await RunSourceFileStore.prepareInBackground(
            source,
            storeURL: storeURL,
            persistThread: false,
            didBegin: { probe.recordCurrentThread() }
        )

        XCTAssertEqual(probe.recordedMainThreadValue, false)
        XCTAssertNotEqual(prepared.runtime.leasePDF, lease)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.runtime.leasePDF.path))
        XCTAssertEqual(prepared.runtime.leasePDF.deletingLastPathComponent().lastPathComponent, "Imported Sources")
    }

    func testSourceFileStorePreservesThreadWhenRequested() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-import-thread-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let lease = root.appendingPathComponent("lease.pdf")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        let storeURL = root.appendingPathComponent("library.json")
        let source = RunSource(
            leasePDF: lease, dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "", baseURL: "",
            apiKey: "secret", thread: "persist me")

        let prepared = try RunSourceFileStore.prepare(source, storeURL: storeURL, persistThread: true)

        XCTAssertEqual(prepared.persisted.thread, "persist me")
        XCTAssertEqual(prepared.persisted.apiKey, "")
    }

    func testSourceFileStoreRemovesCopiedLeaseWhenDealImportFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-import-rollback-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let lease = root.appendingPathComponent("lease.pdf")
        let missingDeal = root.appendingPathComponent("missing.yaml")
        let storeURL = root.appendingPathComponent("library.json")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        let source = RunSource(
            leasePDF: lease, dealSheet: missingDeal, context: "",
            failOn: .error, provider: .codex, model: "", baseURL: "",
            apiKey: "", thread: "")

        XCTAssertThrowsError(try RunSourceFileStore.prepare(source, storeURL: storeURL, persistThread: false))

        let imports = RunSourceFileStore.importsDirectory(forStoreURL: storeURL)
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: imports.path)) ?? []
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSourceFileStoreKeepsAlreadyImportedLeaseWhenDealImportFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-import-keep-retry-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let lease = root.appendingPathComponent("lease.pdf")
        let storeURL = root.appendingPathComponent("library.json")
        try "%PDF-1.4\n".write(to: lease, atomically: true, encoding: .utf8)
        let importedLease = try RunSourceFileStore.importLeasePDF(lease, storeURL: storeURL)
        let source = RunSource(
            leasePDF: importedLease, dealSheet: root.appendingPathComponent("missing.yaml"), context: "",
            failOn: .error, provider: .codex, model: "", baseURL: "",
            apiKey: "", thread: "")

        XCTAssertThrowsError(try RunSourceFileStore.prepare(source, storeURL: storeURL, persistThread: false))

        XCTAssertTrue(FileManager.default.fileExists(atPath: importedLease.path))
    }
}
