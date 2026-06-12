import XCTest
@testable import Redline

final class SourcePDFStateTests: XCTestCase {
    func testExistingPDFIsAvailable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-source-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("lease.pdf")
        try "%PDF-1.4\n".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertEqual(SourcePDFState.state(for: url), .available(url))
    }

    func testMissingPDFIsReported() {
        let url = URL(fileURLWithPath: "/tmp/redline-missing-\(UUID().uuidString).pdf")

        XCTAssertEqual(SourcePDFState.state(for: url), .missing(url))
    }
}
