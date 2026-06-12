import XCTest
@testable import Redline

final class CodableTests: XCTestCase {
    func testReviewDocRoundTrips() throws {
        let original = SampleData.documents[0]
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ReviewDoc.self, from: data)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.findings.count, original.findings.count)
        XCTAssertEqual(restored.verdict.headline, original.verdict.headline)

        // Guard the let→var UUID fix from silent regression: the ids must survive
        // the round trip, not be regenerated on decode.
        XCTAssertFalse(original.facts.isEmpty, "sample must have facts")
        XCTAssertEqual(restored.facts.first?.id, original.facts.first?.id)   // guards KeyTerm let→var
        let origEv = original.allFindings.first(where: { !$0.evidence.isEmpty })
        let restEv = restored.allFindings.first(where: { !$0.evidence.isEmpty })
        XCTAssertNotNil(origEv?.evidence.first?.id)
        XCTAssertEqual(restEv?.evidence.first?.id, origEv?.evidence.first?.id)   // guards ReviewEvidence let→var
    }

    func testRunSourceNeverPersistsAPIKey() throws {
        let src = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/lease.pdf"),
            dealSheet: nil, context: "ctx",
            failOn: .error, provider: .codex,
            model: "m", baseURL: "https://api.example", apiKey: "sk-SECRET-DO-NOT-LEAK")
        let data = try JSONEncoder().encode(src)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("sk-SECRET-DO-NOT-LEAK"), "API key must never appear in serialized output")
        let restored = try JSONDecoder().decode(RunSource.self, from: data)
        XCTAssertEqual(restored.apiKey, "", "apiKey must decode to empty (never persisted)")
        XCTAssertEqual(restored.model, "m")              // non-secret fields still round-trip
        XCTAssertEqual(restored.baseURL, "https://api.example")
    }

    func testDealTermRoundTrips() throws {
        let t = DealTerm(label: "Total rent", expected: "CAD 600,000", actual: "CAD 600,000",
                         verified: true, source: "thread")
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(DealTerm.self, from: data)
        XCTAssertEqual(back.label, t.label)
        XCTAssertEqual(back.verified, t.verified)
        XCTAssertEqual(back.source, "thread")
    }

    func testReviewDocDecodesLegacySnapshotMissingDealTerms() throws {
        // Simulate a pre-1.5 snapshot: encode a current doc, then remove the dealTerms key.
        let doc = SampleData.documents[0]
        let data = try JSONEncoder().encode(doc)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "dealTerms")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let restored = try JSONDecoder().decode(ReviewDoc.self, from: legacy)   // must NOT throw
        XCTAssertTrue(restored.dealTerms.isEmpty)
        XCTAssertEqual(restored.id, doc.id)
    }

    func testRunSourceDecodesLegacySnapshotMissingThread() throws {
        let src = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "m", baseURL: "u",
            apiKey: "sk-SECRET", thread: "x")
        let data = try JSONEncoder().encode(src)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "thread")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let restored = try JSONDecoder().decode(RunSource.self, from: legacy)   // must NOT throw
        XCTAssertEqual(restored.thread, "")
        XCTAssertEqual(restored.apiKey, "")
    }

    func testRunSourceDecodesLegacySnapshotMissingReviewContextState() throws {
        let src = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "m", baseURL: "u",
            apiKey: "sk-SECRET", thread: "saved context")
        let data = try JSONEncoder().encode(src)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "reviewContextState")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let restored = try JSONDecoder().decode(RunSource.self, from: legacy)

        XCTAssertEqual(restored.reviewContextState, .saved)
        XCTAssertEqual(restored.apiKey, "")
    }

    func testRunSourceDecodesLegacySnapshotMissingProfile() throws {
        let src = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil, context: "",
            profile: .leaseMath, failOn: .error, provider: .codex, model: "m", baseURL: "u",
            apiKey: "sk-SECRET", thread: "")
        let data = try JSONEncoder().encode(src)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "profile")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let restored = try JSONDecoder().decode(RunSource.self, from: legacy)

        XCTAssertEqual(restored.profile, .leaseGeneral)
        XCTAssertEqual(restored.apiKey, "")
    }

    func testRunSourceDecodesLegacySnapshotMissingOriginalLeaseFilename() throws {
        var src = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "m", baseURL: "u",
            apiKey: "sk-SECRET", thread: "x")
        src.originalLeaseFilename = "x.pdf"
        let data = try JSONEncoder().encode(src)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "originalLeaseFilename")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let restored = try JSONDecoder().decode(RunSource.self, from: legacy)
        XCTAssertNil(restored.originalLeaseFilename)
        XCTAssertEqual(restored.apiKey, "")
    }

    func testRunSourceOriginalLeaseFilenamePersistsButKeyDoesNot() throws {
        var src = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/imported.pdf"), dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "m", baseURL: "u",
            apiKey: "sk-SECRET", thread: "")
        src.originalLeaseFilename = "Original Lease.pdf"

        let data = try JSONEncoder().encode(src)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("Original Lease.pdf"))
        XCTAssertFalse(json.contains("sk-SECRET"))
        let back = try JSONDecoder().decode(RunSource.self, from: data)
        XCTAssertEqual(back.originalLeaseFilename, "Original Lease.pdf")
        XCTAssertEqual(back.apiKey, "")
    }

    func testRunSourceThreadPersistsButKeyDoesNot() throws {
        let src = RunSource(
            leasePDF: URL(fileURLWithPath: "/tmp/x.pdf"), dealSheet: nil, context: "",
            failOn: .error, provider: .codex, model: "m", baseURL: "u",
            apiKey: "sk-SECRET", thread: "we agreed $600k")
        let data = try JSONEncoder().encode(src)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("we agreed $600k"), "thread must persist")
        XCTAssertFalse(json.contains("sk-SECRET"), "api key must never persist")
        let back = try JSONDecoder().decode(RunSource.self, from: data)
        XCTAssertEqual(back.thread, "we agreed $600k")
        XCTAssertEqual(back.apiKey, "")
    }

    func testDealContextDoesNotSaveThreadByDefault() {
        let context = DealContext(thread: "negotiated terms")

        XCTAssertFalse(context.saveThread)
    }
}
