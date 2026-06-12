import AppKit
import UniformTypeIdentifiers

enum ExportSaveResult: Equatable {
    case written(URL)
    case cancelled
    case failed(String)
}

/// Renders a reviewed document into a cited Markdown review memo — the exportable artifact.
/// Pure (no IO) so it's unit-testable; `ExportWriter.save` (Task 2.4) writes it via NSSavePanel.
enum ExportWriter {
    static func renderMemo(doc: ReviewDoc, reviewer: String? = nil, dateStamp: String? = nil) -> String {
        var out: [String] = []
        let v = plainVerdict(doc)
        out.append("# \(doc.kind) review — \(doc.name)")
        out.append("")
        out.append("**\(v.head)**")
        out.append(v.sub)
        out.append("")

        let attention = doc.findings.filter { $0.bucket == .problem || $0.bucket == .warn }
        if !attention.isEmpty {
            out.append("## Findings")
            for f in attention {
                out.append("")
                out.append("### \(f.headline)")
                if let expected = f.expected {
                    out.append("- In the document: \(f.actual ?? "—") → should be: \(expected)")
                }
                out.append("- \(f.detail)")
                for ev in f.evidence {
                    if let loc = doc.clauseIndex[ev.clause] {
                        out.append("- Cited: “\(ev.quote)” (§\(loc.num) · page \(loc.page))")
                    } else {
                        out.append("- Cited: “\(ev.quote)”")
                    }
                }
            }
            out.append("")
        }

        let passed = doc.findings.filter { $0.severity == .pass }.count
        if passed > 0 { out.append("_\(passed) checks passed._"); out.append("") }

        if !doc.dealTerms.isEmpty {
            let verified = doc.dealTerms.filter { $0.verified }.count
            out.append("## Comparison terms — \(verified) of \(doc.dealTerms.count) verified")
            for t in doc.dealTerms {
                if t.verified {
                    out.append("- [x] \(t.label): \(t.expected) — matches the document (from \(t.source))")
                } else {
                    out.append("- [ ] \(t.label): expected \(t.expected)\(t.actual.map { ", document shows \($0)" } ?? "") (from \(t.source))")
                }
            }
            out.append("")
        }

        if let reviewer, let dateStamp {
            out.append("---")
            out.append("Reviewed by \(reviewer) on \(dateStamp)")
        }
        return out.joined(separator: "\n")
    }
}

extension ExportWriter {
    static func writeMemo(
        doc: ReviewDoc,
        to url: URL,
        reviewer: String? = nil,
        dateStamp: String? = nil
    ) throws -> URL {
        try renderMemo(doc: doc, reviewer: reviewer, dateStamp: dateStamp)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Presents an NSSavePanel and writes the memo as Markdown. Cancel is distinct from a
    /// write failure so the UI can stay quiet on cancel and show a real error on failure.
    @MainActor
    static func save(doc: ReviewDoc, reviewer: String? = nil, dateStamp: String? = nil) -> ExportSaveResult {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(doc.name) — review.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        do {
            return .written(try writeMemo(doc: doc, to: url, reviewer: reviewer, dateStamp: dateStamp))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
