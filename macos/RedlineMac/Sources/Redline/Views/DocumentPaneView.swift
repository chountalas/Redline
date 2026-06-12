import SwiftUI

// MARK: - Clause-text highlighter (punctuation-tolerant, ui2.jsx `highlightText`)

private let rlLeadingStrip = CharacterSet(charactersIn: " \t\n\"'\u{201c}\u{201d}(")
private let rlTrailingStrip = CharacterSet(charactersIn: " \t\n\"'\u{201c}\u{201d}.,;:)")

private func rlNormalizeFragments(_ fragments: [String]) -> [String] {
    var out: [String] = []
    for fragment in fragments {
        for piece in fragment.components(separatedBy: "\u{2026}") {
            var s = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            while let first = s.unicodeScalars.first, rlLeadingStrip.contains(first) { s.removeFirst() }
            while let last = s.unicodeScalars.last, rlTrailingStrip.contains(last) { s.removeLast() }
            if s.count > 5 { out.append(s) }
        }
    }
    return out
}

/// Highlight the cited fragments inside a clause body. Mirrors the design's underlined,
/// accent-tinted `<mark>`; `hl` is the active clause's bucket color (accent for evidence).
func rlHighlight(_ body: String, fragments: [String], hl: Color, ink: Color) -> AttributedString {
    var attr = AttributedString(body)
    attr.foregroundColor = ink
    for part in rlNormalizeFragments(fragments) {
        var searchStart = body.startIndex
        while let range = body.range(of: part, range: searchStart..<body.endIndex) {
            if let lo = AttributedString.Index(range.lowerBound, within: attr),
               let hi = AttributedString.Index(range.upperBound, within: attr) {
                let r = lo..<hi
                attr[r].backgroundColor = hl.opacity(0.18)
                attr[r].underlineStyle = Text.LineStyle(pattern: .solid, color: hl)
            }
            searchStart = range.upperBound
        }
    }
    return attr
}

// MARK: - Document pane

private enum DocumentPaneMode: String, CaseIterable, Identifiable {
    case evidence, source
    var id: String { rawValue }
    var title: String {
        switch self {
        case .evidence: "Evidence"
        case .source: "Source"
        }
    }
}

struct DocumentPaneView: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let doc: ReviewDoc
    var onClose: (() -> Void)? = nil
    @State private var mode: DocumentPaneMode = .evidence

    private var effectiveMode: DocumentPaneMode {
        if doc.source != nil, doc.document.isEmpty { return .source }
        if doc.source == nil { return .evidence }
        return mode
    }

    private var clauseToFinding: [String: ReviewFinding] {
        var map: [String: ReviewFinding] = [:]
        for f in doc.allFindings {
            for e in f.evidence where map[e.clause] == nil { map[e.clause] = f }
        }
        return map
    }

    private var activeClauses: [String: [String]] {
        var map: [String: [String]] = [:]
        if let sel = doc.allFindings.first(where: { $0.id == ws.selFindingID }) {
            for e in sel.evidence { map[e.clause, default: []].append(e.quote) }
        }
        return map
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(rl.line)
            if effectiveMode == .source, let source = doc.source?.leasePDF {
                sourcePane(source)
            } else {
                evidencePane
            }
        }
        .background(rl.docBG)
    }

    private var evidencePane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("rl-doc-top")
                VStack(alignment: .leading, spacing: 0) {
                    if doc.document.isEmpty {
                        sourceFallback
                    } else {
                        ForEach(Array(doc.document.enumerated()), id: \.element.page) { idx, page in
                            pageView(page, isFirst: idx == 0)
                        }
                        Text("End of document")
                            .font(rl.mono(10.5)).tracking(0.4)
                            .foregroundStyle(rl.ink4)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 26)
                .padding(.top, 18)
                .padding(.bottom, 50)
            }
            .onChange(of: ws.scrollTick) { _, _ in
                guard let active = ws.activeClause else { return }
                if reduceMotion {
                    proxy.scrollTo(active, anchor: .top)
                } else {
                    withAnimation(.easeOut(duration: 0.28)) { proxy.scrollTo(active, anchor: .top) }
                }
            }
            .onChange(of: doc.id) { _, _ in
                proxy.scrollTo("rl-doc-top", anchor: .top)
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            RLIcon(doc.type == "lease" ? "lease" : "contract", size: 15)
                .foregroundStyle(rl.accent)
                .frame(width: 30, height: 30)
                .background(rlMix(rl.accent, rl.win, 0.11), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(doc.name).font(rl.ui(13.5, .semibold)).foregroundStyle(rl.ink)
                Text("\(doc.kind) · \(doc.party) · \(doc.pages) pages")
                    .font(rl.ui(12)).foregroundStyle(rl.ink3)
            }
            Spacer(minLength: 8)
            if doc.source != nil {
                Picker("Document view", selection: Binding(
                    get: { effectiveMode },
                    set: { mode = $0 }
                )) {
                    ForEach(DocumentPaneMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 168)
            }
            if let onClose {
                Button(action: onClose) {
                    RLIcon("x", size: 15).foregroundStyle(rl.ink2)
                        .frame(width: 30, height: 30)
                        .background(rl.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(rl.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close document")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(rl.win)
    }

    @ViewBuilder
    private func sourcePane(_ url: URL) -> some View {
        switch SourcePDFState.state(for: url) {
        case .available(let url):
            PDFSourceView(url: url)
                .background(Color(nsColor: .textBackgroundColor))
        case .missing:
            missingSourceView
        }
    }

    private var missingSourceView: some View {
        VStack(spacing: 12) {
            RLIcon("doc", size: 28).foregroundStyle(rl.ink3)
            Text("Source PDF not found")
                .font(rl.serif(20, .medium))
                .foregroundStyle(rl.ink)
            Text("Replace the source PDF from the document menu, then re-check.")
                .font(rl.ui(13))
                .foregroundStyle(rl.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var sourceFallback: some View {
        VStack(spacing: 12) {
            RLIcon("doc", size: 28).foregroundStyle(rl.ink3)
            Text("No cited clauses")
                .font(rl.serif(20, .medium))
                .foregroundStyle(rl.ink)
            Text("Open the source PDF to review the full lease.")
                .font(rl.ui(13))
                .foregroundStyle(rl.ink3)
            if let source = doc.source?.leasePDF {
                Button {
                    ws.openSourcePage(source, page: 1)
                } label: {
                    HStack(spacing: 7) {
                        RLIcon("doc", size: 13)
                        Text("Open source PDF").font(rl.ui(13, .semibold))
                    }
                    .foregroundStyle(rl.win)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(rl.ink, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(.vertical, 40)
    }

    // MARK: page

    private func pageView(_ page: DocPage, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                Divider().overlay(rl.line).padding(.bottom, 26)
            }
            HStack {
                Text(doc.name)
                Spacer()
                Text("Page \(page.page) of \(doc.pages)")
            }
            .font(rl.mono(10)).tracking(0.3).textCase(.uppercase)
            .foregroundStyle(rl.ink4)
            .padding(.bottom, 15)

            Text(page.heading)
                .font(rl.serif(20, .medium))
                .foregroundStyle(rl.ink)
                .padding(.bottom, 10)

            ForEach(page.clauses) { clause in
                clauseRow(clause)
                    .id(clause.id)
            }
        }
        .padding(.bottom, 30)
    }

    // MARK: clause

    private func clauseRow(_ clause: Clause) -> some View {
        let owner = clauseToFinding[clause.id]
        let bucket = owner?.bucket
        let cl = bucket.map { rl.color($0) } ?? rl.accent
        let isActive = activeClauses[clause.id] != nil
        let isProblem = bucket == .problem || bucket == .warn
        return ClauseRow(
            clause: clause,
            cl: cl,
            isActive: isActive,
            isProblem: isProblem,
            bucket: bucket,
            quotes: activeClauses[clause.id] ?? [],
            clickable: owner != nil,
            onTap: { if let owner { ws.jumpClause(clause.evidenceClauseOr(owner)) } }
        )
    }
}

private extension Clause {
    /// When a clause is clicked, jump using its own id (it owns the active highlight).
    func evidenceClauseOr(_ finding: ReviewFinding) -> String { id }
}

// MARK: - Clause row (own view for hover state)

private struct ClauseRow: View {
    @Environment(\.rl) private var rl
    let clause: Clause
    let cl: Color
    let isActive: Bool
    let isProblem: Bool
    let bucket: Bucket?
    let quotes: [String]
    let clickable: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            if clickable {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(clause.title), section \(clause.num)")
                .accessibilityHint("Shows the related finding")
            } else {
                rowContent
            }
        }
        .onHover { if clickable { hovering = $0 } }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                Text("§\(clause.num)")
                    .font(rl.mono(11.5)).foregroundStyle(rl.ink3)
                if isProblem, let bucket {
                    BucketGlyph(bucket: bucket, size: 11).foregroundStyle(cl)
                        .accessibilityLabel(bucket == .problem ? "Problem" : "Heads-up")
                }
            }
            .frame(width: 44, alignment: .leading)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(clause.title)
                    .font(rl.ui(10.5, .bold)).tracking(0.5).textCase(.uppercase)
                    .foregroundStyle(rl.ink3)
                clauseText
            }
        }
        .padding(13)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var clauseText: some View {
        if isActive {
            Text(rlHighlight(clause.text, fragments: quotes, hl: cl, ink: rl.ink))
                .font(rl.serif(rl.docSize)).lineSpacing(rl.docSize * 0.5)
        } else {
            Text(clause.text)
                .font(rl.serif(rl.docSize)).lineSpacing(rl.docSize * 0.5)
                .foregroundStyle(rl.ink)
        }
    }

    private var background: Color {
        if isActive { return rlMix(cl, rl.docBG, 0.08) }
        if hovering { return rl.surface2 }
        return .clear
    }
}
