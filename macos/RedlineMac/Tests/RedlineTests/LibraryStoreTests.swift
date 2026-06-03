import XCTest
@testable import Redline

final class LibraryStoreTests: XCTestCase {
    func testSaveThenLoadRoundTrips() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let snap = LibrarySnapshot(
            documents: SampleData.documents,
            groups: SampleData.groups,
            selectedDocID: SampleData.documents[0].id,
            reviewed: ["d1:R1": true],
            notes: ["d1:R1": "looks off"]
        )
        try LibraryStore.save(snap, to: tmp)
        let loaded = try XCTUnwrap(LibraryStore.load(from: tmp))
        XCTAssertEqual(loaded.documents.count, snap.documents.count)
        XCTAssertEqual(loaded.reviewed["d1:R1"], true)
        XCTAssertEqual(loaded.notes["d1:R1"], "looks off")
    }

    func testLoadMissingFileReturnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        XCTAssertNil(LibraryStore.load(from: missing))
    }

    func testLoadCorruptFileQuarantinesAndReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("library.json")
        try Data("{ not valid json".utf8).write(to: url)

        XCTAssertNil(LibraryStore.load(from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "corrupt file must be moved aside")
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("library.corrupt-") }
        XCTAssertEqual(quarantined.count, 1, "corrupt file should be quarantined exactly once")
    }
}
