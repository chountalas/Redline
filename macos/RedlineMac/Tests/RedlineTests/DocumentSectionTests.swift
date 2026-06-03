import XCTest
@testable import Redline

@MainActor
final class DocumentSectionTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-orphan-\(UUID().uuidString).json")
    }

    func testOrphanDocumentIsStillRenderedAndSelectable() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = SampleData.documents[0]
        let snap = LibrarySnapshot(
            documents: [doc],
            groups: [],
            selectedDocID: doc.id,
            reviewed: [:],
            notes: [:]
        )
        try LibraryStore.save(snap, to: url)

        let ws = Workspace(storeURL: url)
        let sections = docListSections(documents: ws.documents, groups: ws.groups)

        XCTAssertEqual(sections.map(\.label), ["Your documents"])
        XCTAssertEqual(sections.flatMap(\.documents).map(\.id), [doc.id])

        ws.selectDoc(doc.id)
        XCTAssertEqual(ws.screen, .workspace)
        XCTAssertEqual(ws.selectedDocID, doc.id)
    }

    func testUngroupedDocumentsAreAppendedWithoutDuplicatingGroupedDocs() {
        let grouped = SampleData.documents[0]
        let orphan = SampleData.documents[1]
        let sections = docListSections(
            documents: [grouped, orphan],
            groups: [DocGroup(id: "leases", label: "Leases", ids: [grouped.id])]
        )

        XCTAssertEqual(sections.map(\.label), ["Leases", "Your documents"])
        XCTAssertEqual(sections[0].documents.map(\.id), [grouped.id])
        XCTAssertEqual(sections[1].documents.map(\.id), [orphan.id])
    }
}
