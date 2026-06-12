import XCTest
@testable import Redline

final class ExportWriterTests: XCTestCase {
    func testMemoIncludesVerdictFindingsAndDealTerms() {
        let memo = ExportWriter.renderMemo(doc: SampleData.pembina)
        XCTAssertTrue(memo.contains("100 Sample Highway"))          // doc name
        XCTAssertTrue(memo.contains("One issue to resolve before approval")) // plainVerdict.head
        XCTAssertTrue(memo.contains("Per-face rent doesn’t add up to the stated total.")) // a finding headline
        XCTAssertTrue(memo.contains("CAD 800,000.00"))             // expected
        XCTAssertTrue(memo.contains("CAD 400,000.00"))             // actual
        XCTAssertTrue(memo.contains("Comparison terms — 0 of 1 verified"))
        XCTAssertTrue(memo.contains("expected CAD 250,000"))       // mismatch term
        XCTAssertTrue(memo.contains("document shows CAD 400,000"))
    }

    func testCleanDocListsVerifiedDealTerms() {
        let memo = ExportWriter.renderMemo(doc: SampleData.idylwyld)
        XCTAssertTrue(memo.contains("Comparison terms — 3 of 3 verified"))
        XCTAssertTrue(memo.contains("Total rent"))
        XCTAssertTrue(memo.contains("CAD 600,000"))
    }

    func testReviewerFooterStampedOnlyWhenBothProvided() {
        let plain = ExportWriter.renderMemo(doc: SampleData.idylwyld)
        XCTAssertFalse(plain.contains("Reviewed by"))
        let stamped = ExportWriter.renderMemo(doc: SampleData.idylwyld, reviewer: "Reviewer", dateStamp: "2026-06-03")
        XCTAssertTrue(stamped.contains("Reviewed by Reviewer on 2026-06-03"))
    }

    func testWriteMemoReturnsWrittenURL() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-export-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("memo.md")
        let written = try ExportWriter.writeMemo(doc: SampleData.documents[0], to: url)

        XCTAssertEqual(written, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWriteMemoSurfacesWriteFailures() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-export-missing-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("memo.md")

        XCTAssertThrowsError(try ExportWriter.writeMemo(doc: SampleData.documents[0], to: url))
    }
}
