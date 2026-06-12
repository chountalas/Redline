import XCTest
@testable import Redline

final class ReviewContextBuilderTests: XCTestCase {
    func testAppendingTemplatePreservesExistingContext() {
        let result = ReviewContextBuilder.appending(.approvalConstraints, to: "Expected price is CAD 10,000.")

        XCTAssertTrue(result.contains("Expected price is CAD 10,000."))
        XCTAssertTrue(result.contains("Approval constraints:"))
        XCTAssertTrue(result.contains("\n\nApproval constraints:"))
    }

    func testAdvisoryFocusCombinesFocusAndReviewContext() {
        let result = ReviewContextBuilder.advisoryFocus(
            explicitFocus: "Check termination.",
            reviewContext: "Cannot accept auto-renewal."
        )

        XCTAssertTrue(result.contains("Focus note:\nCheck termination."))
        XCTAssertTrue(result.contains("Review context:\nCannot accept auto-renewal."))
    }

    func testAdvisoryFocusUsesReviewContextWhenFocusIsBlank() {
        let result = ReviewContextBuilder.advisoryFocus(
            explicitFocus: "   ",
            reviewContext: "Need mutual NDA terms."
        )

        XCTAssertEqual(result, "Review context:\nNeed mutual NDA terms.")
    }
}
