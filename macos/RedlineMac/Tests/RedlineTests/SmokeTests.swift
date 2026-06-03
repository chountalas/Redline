import XCTest
@testable import Redline

final class SmokeTests: XCTestCase {
    func testSampleDataLoads() {
        XCTAssertFalse(SampleData.documents.isEmpty, "bundled samples should exist")
    }
}
