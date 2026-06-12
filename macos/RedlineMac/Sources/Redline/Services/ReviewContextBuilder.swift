import Foundation

enum ReviewContextTemplate: String, CaseIterable, Identifiable {
    case expectedTerms
    case reviewLens
    case approvalConstraints
    case openQuestions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expectedTerms: "Expected terms"
        case .reviewLens: "Risk lens"
        case .approvalConstraints: "Approval notes"
        case .openQuestions: "Open questions"
        }
    }

    var text: String {
        switch self {
        case .expectedTerms:
            """
            Expected terms:
            - Parties:
            - Effective date:
            - Term / renewal:
            - Payment / fees:
            - Key obligations:
            """
        case .reviewLens:
            """
            Risk lens:
            - Flag unusual liability, indemnity, termination, renewal, assignment, confidentiality, exclusivity, payment, audit, or governing-law terms.
            - Call out anything that conflicts with the business context below.
            """
        case .approvalConstraints:
            """
            Approval constraints:
            - Must have:
            - Cannot accept:
            - Needs human/legal review if:
            """
        case .openQuestions:
            """
            Open questions:
            -
            """
        }
    }
}

enum ReviewContextBuilder {
    static func appending(_ addition: String, to current: String) -> String {
        let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddition.isEmpty else { return current }
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCurrent.isEmpty else { return trimmedAddition }
        return trimmedCurrent + "\n\n" + trimmedAddition
    }

    static func appending(_ template: ReviewContextTemplate, to current: String) -> String {
        appending(template.text, to: current)
    }

    static func advisoryFocus(explicitFocus: String, reviewContext: String) -> String {
        var parts: [String] = []
        let focus = explicitFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focus.isEmpty {
            parts.append("Focus note:\n" + focus)
        }
        let context = reviewContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.isEmpty {
            parts.append("Review context:\n" + context)
        }
        return parts.joined(separator: "\n\n")
    }
}
