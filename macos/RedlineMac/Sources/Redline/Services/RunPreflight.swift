import Foundation

struct RunPreflightResult: Equatable {
    let canRun: Bool
    let message: String?

    static let ready = RunPreflightResult(canRun: true, message: nil)
    static func blocked(_ message: String) -> RunPreflightResult {
        RunPreflightResult(canRun: false, message: message)
    }
}

enum RunPreflight {
    static func validate(
        leasePDF: URL?,
        dealSheet: URL?,
        provider: LLMProvider,
        model: String,
        baseURL: String,
        apiKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RunPreflightResult {
        guard let leasePDF else { return .blocked("Choose a lease PDF.") }
        guard RunSheetFileIntake.isPDF(leasePDF) else { return .blocked("Use a PDF lease.") }

        if let dealSheet, !RunSheetFileIntake.isDealSheet(dealSheet) {
            return .blocked("Deal sheet must be a .yaml or .yml file.")
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = trimmedModel.isEmpty ? envModel(for: provider, environment: environment) : trimmedModel
        let effectiveKey = trimmedKey.isEmpty ? envAPIKey(for: provider, environment: environment) : trimmedKey

        switch provider {
        case .openai:
            if effectiveModel.isEmpty { return .blocked("OpenAI runs need a model.") }
            if effectiveKey.isEmpty { return .blocked("OpenAI runs need an API key.") }
        case .anthropic:
            if effectiveModel.isEmpty { return .blocked("Anthropic runs need a model.") }
            if effectiveKey.isEmpty { return .blocked("Anthropic runs need an API key.") }
        case .codex, .ollama:
            break
        }

        return .ready
    }

    private static func envModel(for provider: LLMProvider, environment: [String: String]) -> String {
        let providerKey = provider.rawValue.uppercased()
        return firstNonBlank([
            environment["REDLINE_MODEL"],
            environment["REDLINE_\(providerKey)_MODEL"],
        ])
    }

    private static func envAPIKey(for provider: LLMProvider, environment: [String: String]) -> String {
        switch provider {
        case .openai:
            return firstNonBlank([environment["REDLINE_API_KEY"], environment["OPENAI_API_KEY"]])
        case .anthropic:
            return firstNonBlank([environment["REDLINE_API_KEY"], environment["ANTHROPIC_API_KEY"]])
        case .codex, .ollama:
            return ""
        }
    }

    private static func firstNonBlank(_ values: [String?]) -> String {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
