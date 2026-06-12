import Foundation

// MARK: - Severity & buckets
//
// The v2 design collapses the engine's loud severities into a few things a reader
// actually cares about (see ui2.jsx `bucket`):
//   error            → problem  (must resolve before approval)
//   warn / verify    → warn     (worth a look, won't block)
//   info             → note     (informational)
//   advisory         → ai       (AI suggestion, segregated)
//   skip             → skip     (not checked; folded away)
//   pass             → pass      (fine; folded away)

enum Bucket: String, Codable {
    case problem, warn, note, ok, pass, ai, skip
}

enum Severity: String, Codable {
    case error, warn, verify, info, advisory, pass, skip

    var bucket: Bucket {
        switch self {
        case .error: .problem
        case .warn, .verify: .warn
        case .info: .note
        case .advisory: .ai
        case .skip: .skip
        case .pass: .pass
        }
    }

    /// Short plain-language label for a secondary/passed check (ui2.jsx SHORT).
    var shortLabel: String {
        switch bucket {
        case .pass: "Passed"
        case .note: "Note"
        case .skip: "Not checked"
        case .warn: "Heads-up"
        case .problem: "Problem"
        case .ai: "AI"
        case .ok: "Passed"
        }
    }
}

// MARK: - Layout directions (the single "Layout" tweak, now a real view mode)
// Named RLLayout to avoid colliding with SwiftUI's `Layout` protocol.

enum RLLayout: String, CaseIterable, Identifiable, Codable {
    case focused, split, report
    var id: String { rawValue }
    var title: String {
        switch self {
        case .focused: "Focused"
        case .split: "Split"
        case .report: "Report"
        }
    }
}

// MARK: - Document model (mirrors window.REDLINE)

struct ReviewEvidence: Identifiable, Codable {
    var id = UUID()
    var clause: String   // clause id, e.g. "p2-rent" (empty when there is no structured clause)
    var quote: String
}

struct ReviewFinding: Identifiable, Codable {
    let id: String       // selection id, e.g. "R2", "X1", "A1"
    var rule: String
    var severity: Severity
    var title: String
    var detail: String
    var plain: String? = nil
    var expected: String? = nil
    var actual: String? = nil
    var evidence: [ReviewEvidence] = []

    var bucket: Bucket { severity.bucket }
    var headline: String { plain ?? title }
    var firstClause: String? { evidence.first?.clause }
}

struct Clause: Identifiable, Codable {
    let id: String       // "p2-rent"
    var num: String      // "2.1"
    var title: String
    var text: String
}

struct DocPage: Identifiable, Codable {
    var page: Int
    var heading: String
    var clauses: [Clause]
    var id: Int { page }
}

struct KeyTerm: Identifiable, Codable {
    var id = UUID()
    var k: String
    var v: String
    var flag: Bool = false
}

struct DealTerm: Identifiable, Codable {
    var id = UUID()
    var label: String
    var expected: String
    var actual: String? = nil
    var verified: Bool
    var source: String   // "deal.yaml" | "thread"
}

enum ReviewContextState: String, Codable, Sendable {
    case none
    case saved
    case unsaved
}

struct Verdict: Codable {
    var level: String   // "error" | "pass"
    var headline: String
    var lead: String    // finding id to auto-select on open
    var sub: String
}

/// Inputs captured for an engine-backed document so "Re-check" can re-run it.
struct RunSource: Codable, Sendable {
    var leasePDF: URL
    var originalLeaseFilename: String? = nil
    var dealSheet: URL?
    var context: String
    var profile: ReviewProfile = .leaseGeneral
    var failOn: FailOn
    var provider: LLMProvider
    var model: String
    var baseURL: String
    var apiKey: String = ""   // transient — NEVER persisted (excluded below)
    var thread: String = ""   // negotiation thread; persisted (unlike apiKey)
    var reviewContextState: ReviewContextState = .none

    private enum CodingKeys: String, CodingKey {
        case leasePDF, originalLeaseFilename, dealSheet, context, profile
        case failOn, provider, model, baseURL
        case thread, reviewContextState
        // apiKey deliberately excluded — the API key is never written to disk
    }
}

extension RunSource {
    // Custom decode so a legacy snapshot missing `thread` falls back to "" instead of
    // throwing keyNotFound (which would make LibraryStore.load wipe the library). Declared
    // in an extension so the synthesized memberwise init (apiKey:/thread:) is preserved;
    // Encodable stays synthesized — encoding still omits apiKey via CodingKeys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leasePDF = try c.decode(URL.self, forKey: .leasePDF)
        originalLeaseFilename = try c.decodeIfPresent(String.self, forKey: .originalLeaseFilename)
        dealSheet = try c.decodeIfPresent(URL.self, forKey: .dealSheet)
        context = try c.decode(String.self, forKey: .context)
        profile = try c.decodeIfPresent(ReviewProfile.self, forKey: .profile) ?? .leaseGeneral
        failOn = try c.decode(FailOn.self, forKey: .failOn)
        provider = try c.decode(LLMProvider.self, forKey: .provider)
        model = try c.decode(String.self, forKey: .model)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        thread = try c.decodeIfPresent(String.self, forKey: .thread) ?? ""
        reviewContextState = try c.decodeIfPresent(ReviewContextState.self, forKey: .reviewContextState)
            ?? (thread.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .none : .saved)
        // apiKey intentionally NOT decoded — never persisted; stays "" via its default.
    }
}

struct ReviewDoc: Identifiable, Codable {
    let id: String
    var name: String
    var kind: String
    var type: String    // "lease" | "contract"
    var party: String
    var pages: Int
    var deal: Bool
    var verdict: Verdict
    var facts: [KeyTerm]
    var findings: [ReviewFinding]
    var advisory: [ReviewFinding]
    var dealTerms: [DealTerm] = []
    var document: [DocPage]
    var source: RunSource? = nil

    var allFindings: [ReviewFinding] { findings + advisory }

    /// Map every clause id to its (number, page) for inline finding locations.
    var clauseIndex: [String: (num: String, page: Int)] {
        var map: [String: (String, Int)] = [:]
        for page in document {
            for clause in page.clauses { map[clause.id] = (clause.num, page.page) }
        }
        return map
    }
}

extension ReviewDoc {
    // Custom decode so a legacy snapshot missing `dealTerms` falls back to [] instead of
    // throwing keyNotFound (which would make LibraryStore.load wipe the library). Declared
    // in an extension so the synthesized memberwise init (used by SampleData) is preserved;
    // Encodable stays synthesized too, so all keys are still written on encode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(String.self, forKey: .kind)
        type = try c.decode(String.self, forKey: .type)
        party = try c.decode(String.self, forKey: .party)
        pages = try c.decode(Int.self, forKey: .pages)
        deal = try c.decode(Bool.self, forKey: .deal)
        verdict = try c.decode(Verdict.self, forKey: .verdict)
        facts = try c.decode([KeyTerm].self, forKey: .facts)
        findings = try c.decode([ReviewFinding].self, forKey: .findings)
        advisory = try c.decode([ReviewFinding].self, forKey: .advisory)
        dealTerms = try c.decodeIfPresent([DealTerm].self, forKey: .dealTerms) ?? []
        document = try c.decode([DocPage].self, forKey: .document)
        source = try c.decodeIfPresent(RunSource.self, forKey: .source)
    }
}

struct DocGroup: Identifiable, Codable {
    let id: String      // "leases" | "contracts" | "yours"
    var label: String
    var ids: [String]
}

// MARK: - Derived presentation logic (ported from the JSX)

struct DocStatus {
    var bucket: Bucket   // .problem | .warn | .ok
    var word: String
}

/// library2.jsx `docStatus` — derived from real findings, not a stored summary.
func docStatus(_ doc: ReviewDoc) -> DocStatus {
    let errors = doc.findings.filter { $0.severity == .error }.count
    if errors > 0 {
        return DocStatus(bucket: .problem, word: errors > 1 ? "\(errors) problems" : "1 problem")
    }
    let looks = doc.findings.filter { $0.severity == .warn || $0.severity == .verify }.count
    if looks > 0 { return DocStatus(bucket: .warn, word: "needs a look") }
    return DocStatus(bucket: .ok, word: "clean")
}

struct PlainVerdict {
    var level: Bucket   // .problem | .ok — drives the verdict marker + eyebrow color
    var eyebrow: String
    var head: String
    var sub: String
}

/// report2.jsx `plainVerdict` — one number + one sentence, in plain English.
func plainVerdict(_ doc: ReviewDoc) -> PlainVerdict {
    let problems = doc.findings.filter { $0.severity == .error }.count
    let looks = doc.findings.filter { $0.severity == .warn || $0.severity == .verify }.count
    let ran = doc.findings.filter { $0.severity != .skip }.count

    if problems > 0 {
        return PlainVerdict(
            level: .problem,
            eyebrow: "Review before approval",
            head: problems == 1 ? "One issue to resolve before approval"
                                : "\(problems) issues to resolve before approval",
            sub: doc.verdict.sub
        )
    }
    if looks > 0 {
        return PlainVerdict(
            level: .ok,
            eyebrow: "Nothing blocking",
            head: "Ready for approval — a couple of things worth a look",
            sub: doc.verdict.sub
        )
    }
    return PlainVerdict(
        level: .ok,
        eyebrow: "Cleared for approval",
        head: "Ready for approval",
        sub: "All \(ran) checks passed" + (doc.deal ? ", including a match against your comparison sheet." : ".")
    )
}
