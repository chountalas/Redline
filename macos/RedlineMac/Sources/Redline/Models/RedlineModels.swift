import Foundation

enum FailOn: String, CaseIterable, Identifiable, Codable {
    case error
    case warn
    case verify
    case advisory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .error: "Error"
        case .warn: "Warn"
        case .verify: "Verify"
        case .advisory: "Advisory"
        }
    }
}

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case codex
    case openai
    case ollama
    case anthropic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex Subscription"
        case .openai: "OpenAI API"
        case .ollama: "Ollama Local"
        case .anthropic: "Anthropic"
        }
    }

    /// Compact label for the run modal's read-only provider chip.
    var shortTitle: String {
        switch self {
        case .codex: "Codex"
        case .openai: "OpenAI"
        case .ollama: "Ollama"
        case .anthropic: "Anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .codex: ""
        case .openai: ""
        case .ollama: "gpt-oss:20b"
        case .anthropic: ""
        }
    }

    var modelPlaceholder: String {
        switch self {
        case .codex: "default subscription model"
        case .openai: "model required"
        case .ollama: defaultModel
        case .anthropic: "model required"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama: "http://localhost:11434"
        default: ""
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .codex: "No API key needed"
        case .openai: "OpenAI API key"
        case .anthropic: "Anthropic API key"
        case .ollama: "No API key needed"
        }
    }
}

struct DealTermJSON: Decodable {
    let label: String
    let expected: String
    let actual: String?
    let verified: Bool
    let source: String
}

struct CheckReport: Decodable {
    let factsSummary: FactsSummary?
    let deterministicFindings: [Finding]
    let advisoryFindings: [Finding]
    let couldNotVerify: [Finding]
    let dealTerms: [DealTermJSON]?
    let summary: Summary
    let exitCode: Int

    enum CodingKeys: String, CodingKey {
        case factsSummary = "facts_summary"
        case deterministicFindings = "deterministic_findings"
        case advisoryFindings = "advisory_findings"
        case couldNotVerify = "could_not_verify"
        case dealTerms = "deal_terms"
        case summary
        case exitCode = "exit_code"
    }
}

/// The engine's `facts_summary` block (report.py). Every field is optional because
/// extraction may leave any value unknown.
struct FactsSummary: Decodable {
    let sourceFile: String?
    let pageCount: Int?
    let statedTotalRent: String?
    let rentBasis: String?
    let perFaceRent: String?
    let numDisplayFaces: Int?
    let baseTermYears: String?

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case pageCount = "page_count"
        case statedTotalRent = "stated_total_rent"
        case rentBasis = "rent_basis"
        case perFaceRent = "per_face_rent"
        case numDisplayFaces = "num_display_faces"
        case baseTermYears = "base_term_years"
    }
}

struct Finding: Decodable, Identifiable {
    var id: String { "\(ruleID)-\(severity)-\(title)-\(detail)" }

    let ruleID: String
    let severity: String
    let title: String
    let detail: String
    let evidence: [Evidence]
    let expected: String?
    let actual: String?

    enum CodingKeys: String, CodingKey {
        case ruleID = "rule_id"
        case severity
        case title
        case detail
        case evidence
        case expected
        case actual
    }
}

struct Evidence: Decodable, Identifiable {
    var id: String { "\(page.map(String.init) ?? "unknown")-\(quote ?? "")" }

    let quote: String?
    let page: Int?
}

struct Summary: Decodable {
    let error: Int
    let warn: Int
    let info: Int
    let couldNotVerify: Int
    let advisory: Int

    enum CodingKeys: String, CodingKey {
        case error
        case warn
        case info
        case couldNotVerify = "could_not_verify"
        case advisory
    }
}

// Engine severity styling now lives in the v2 design system (Theme + Bucket).
