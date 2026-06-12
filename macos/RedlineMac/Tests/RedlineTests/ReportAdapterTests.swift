import XCTest
@testable import Redline

final class ReportAdapterTests: XCTestCase {
    func testDealTermsAreMappedOntoDoc() throws {
        let json = """
        {
          "facts_summary": null,
          "profile": {"id":"lease-general","name":"General lease","version":"1","description":"general"},
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
        XCTAssertEqual(doc.kind, "General lease review")
        XCTAssertEqual(doc.party, "Uploaded PDF")
        XCTAssertEqual(doc.dealTerms.count, 1)
        XCTAssertEqual(doc.dealTerms.first?.label, "Total rent")
        XCTAssertEqual(doc.dealTerms.first?.expected, "CAD 600,000")
        XCTAssertEqual(doc.dealTerms.first?.actual, "CAD 600,000")
        XCTAssertEqual(doc.dealTerms.first?.source, "thread")
        XCTAssertTrue(doc.dealTerms.first?.verified ?? false)
        XCTAssertTrue(doc.deal, "a doc with comparison terms should badge as comparison-aware")
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
        XCTAssertEqual(doc.kind, "General lease review")
        XCTAssertTrue(doc.dealTerms.isEmpty)
        XCTAssertFalse(doc.deal, "no comparison sheet and no comparison terms → not comparison-aware")
    }

    func testDocumentNameUsesOriginalLeaseNameInsteadOfImportedStorageName() throws {
        let json = """
        {
          "facts_summary": {"source_file":"3E4F-storage-lease.pdf","page_count":1},
          "deterministic_findings": [],
          "advisory_findings": [],
          "could_not_verify": [],
          "summary": {"error":0,"warn":0,"info":0,"could_not_verify":0,"advisory":0},
          "exit_code": 0
        }
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(CheckReport.self, from: json)
        var src = RunSource(leasePDF: URL(fileURLWithPath: "/tmp/Imported Sources/3E4F-storage-lease.pdf"),
                            dealSheet: nil, context: "", failOn: .error, provider: .codex,
                            model: "m", baseURL: "u", apiKey: "", thread: "")
        src.originalLeaseFilename = "original lease.pdf"

        let doc = ReportAdapter.makeDoc(from: report, source: src, id: "named")

        XCTAssertEqual(doc.name, "original lease")
    }

    func testCouldNotVerifyFindingsRenderEvenWhenNotDuplicatedInDeterministicFindings() throws {
        let json = """
        {
          "facts_summary": {"source_file":"contract.pdf","page_count":1},
          "deterministic_findings": [],
          "advisory_findings": [],
          "could_not_verify": [
            {
              "rule_id":"R5_term_date_coherence",
              "severity":"COULD_NOT_VERIFY",
              "title":"Could not verify expiry date",
              "detail":"The extracted facts did not include an expiry date.",
              "evidence":[{"quote":"Term begins January 1, 2026","page":1}],
              "expected":null,
              "actual":null
            }
          ],
          "summary": {"error":0,"warn":0,"info":0,"could_not_verify":1,"advisory":0},
          "exit_code": 0
        }
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(CheckReport.self, from: json)
        let src = RunSource(leasePDF: URL(fileURLWithPath: "/tmp/contract.pdf"), dealSheet: nil,
                            context: "", failOn: .error, provider: .codex, model: "m",
                            baseURL: "u", apiKey: "", thread: "")

        let doc = ReportAdapter.makeDoc(from: report, source: src, id: "verify")

        XCTAssertEqual(doc.findings.count, 1)
        XCTAssertEqual(doc.findings.first?.severity, .verify)
        XCTAssertEqual(doc.findings.first?.title, "Could not verify expiry date")
        XCTAssertEqual(doc.verdict.sub, "A couple of items are worth a look — none of them block approval.")
    }
}
