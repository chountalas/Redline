import XCTest
@testable import Redline

final class DealSourceTests: XCTestCase {
    func testManualDealSourcePrefillsNothing() async {
        let prefill = await ManualDealSource().prefill()
        XCTAssertNil(prefill, "the shipped manual source does not auto-pull a deal context")
    }

    func testSampleHasDealTermsForThePanelDemo() {
        let withTerms = SampleData.documents.contains { !$0.dealTerms.isEmpty }
        XCTAssertTrue(withTerms, "at least one bundled sample must show the deal-terms panel")
    }
}
