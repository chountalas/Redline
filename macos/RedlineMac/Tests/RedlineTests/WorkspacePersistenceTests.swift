import XCTest
@testable import Redline

@MainActor
final class WorkspacePersistenceTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-ws-\(UUID().uuidString).json")
    }

    func testEmptyLibraryHasNoCurrentDocAndStaysHome() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rl-empty-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let ws = Workspace(storeURL: url)            // no snapshot → empty library
        XCTAssertTrue(ws.documents.isEmpty)
        XCTAssertNil(ws.currentDoc)                  // must be optional, must not crash
        XCTAssertEqual(ws.screen, .home)
    }

    func testMutationsPersistAndRestoreAcrossInstances() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws1 = Workspace(storeURL: url)
        ws1.loadExamples()
        let docID = ws1.selectedDocID
        let fid = try XCTUnwrap(ws1.currentDoc?.findings.first).id
        ws1.toggleReviewed(fid)
        ws1.setNote(fid, "check this")

        let ws2 = Workspace(storeURL: url)
        XCTAssertEqual(ws2.documents.count, ws1.documents.count)
        XCTAssertEqual(ws2.selectedDocID, docID)
        XCTAssertTrue(ws2.isReviewed(fid), "reviewed flag should restore")
        XCTAssertEqual(ws2.note(fid), "check this", "note should restore")
    }

    func testPersistedLibraryNeverContainsAPIKey() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ws = Workspace(storeURL: url)
        ws.loadExamples()
        // Put a document carrying a RunSource WITH a secret key into the library, then
        // trigger a persist via a normal mutation. Use REAL FailOn/LLMProvider cases.
        var doc = try XCTUnwrap(ws.documents.first)
        doc.source = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil, context: "",
            failOn: .error, provider: .codex,
            model: "m", baseURL: "https://api.example", apiKey: "sk-WORKSPACE-SECRET")
        ws.documents = [doc]
        ws.selectedDocID = doc.id
        ws.toggleReviewed(try XCTUnwrap(doc.findings.first).id)   // triggers persist()

        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains("sk-WORKSPACE-SECRET"), "API key must never reach the library file")
    }
}
