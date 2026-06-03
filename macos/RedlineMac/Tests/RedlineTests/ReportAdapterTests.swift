import XCTest
@testable import Redline

final class ReportAdapterTests: XCTestCase {
    func testDealTermsAreMappedOntoDoc() throws {
        let json = """
        {
          "facts_summary": null,
          "deterministic_findings": [],
          "advisory_findings": [],
          "could_not_verify": [],
          "deal_terms": [
            {"label":"Total rent","expected":"CAD 600,000","actual":"CAD 600,000","verified":true,"source":"thread"}
          ],
          "summary": {"error":0,"warn":0,"info":0,"could_not_verify":0,"advisory":0},
          "exit_code": 0
        }
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(CheckReport.self, from: json)
        let src = RunSource(leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil,
                            context: "", failOn: .error, provider: .codex, model: "m",
                            baseURL: "u", apiKey: "", thread: "we agreed $600k")
        let doc = ReportAdapter.makeDoc(from: report, source: src, id: "t1")
        XCTAssertEqual(doc.dealTerms.count, 1)
        XCTAssertEqual(doc.dealTerms.first?.label, "Total rent")
        XCTAssertEqual(doc.dealTerms.first?.expected, "CAD 600,000")
        XCTAssertEqual(doc.dealTerms.first?.actual, "CAD 600,000")
        XCTAssertEqual(doc.dealTerms.first?.source, "thread")
        XCTAssertTrue(doc.dealTerms.first?.verified ?? false)
        XCTAssertTrue(doc.deal, "a doc with deal terms should badge as deal-aware")
    }

    func testNoDealTermsLeavesDocEmpty() throws {
        // Back-compat path: engine JSON without a deal_terms key (dealTerms is optional).
        let json = """
        {
          "facts_summary": null,
          "deterministic_findings": [],
          "advisory_findings": [],
          "could_not_verify": [],
          "summary": {"error":0,"warn":0,"info":0,"could_not_verify":0,"advisory":0},
          "exit_code": 0
        }
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(CheckReport.self, from: json)
        let src = RunSource(leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil,
                            context: "", failOn: .error, provider: .codex, model: "m",
                            baseURL: "u", apiKey: "", thread: "")
        let doc = ReportAdapter.makeDoc(from: report, source: src, id: "t2")
        XCTAssertTrue(doc.dealTerms.isEmpty)
        XCTAssertFalse(doc.deal, "no deal sheet and no deal terms → not deal-aware")
    }
}
