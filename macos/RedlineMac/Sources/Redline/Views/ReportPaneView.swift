import SwiftUI

/// The report pane: one plain-language verdict up top, only what needs attention shown
/// as cards (with the fix preview inline), everything that passed folded into a quiet
/// line, AI suggestions clearly separated. No colored left-border bars (the design's
/// final note: "classic AI design") — severity lives in the status badge.
struct ReportPaneView: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    let doc: ReviewDoc

    @State private var passOpen = false
    @State private var termsOpen = false
    @State private var exported = false

    private var attention: [ReviewFinding] {
        doc.findings.filter { $0.bucket == .problem || $0.bucket == .warn }
            .sorted { ($0.bucket == .problem ? 0 : 1) < ($1.bucket == .problem ? 0 : 1) }
    }
    private var secondary: [ReviewFinding] {
        doc.findings.filter { !($0.bucket == .problem || $0.bucket == .warn) }
    }
    private var passedCount: Int { secondary.filter { $0.severity != .skip }.count }

    var body: some View {
        @Bindable var ws = ws
        return VStack(spacing: 0) {
            verdict
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !attention.isEmpty {
                        groupHead("Needs your attention", color: rl.ink3)
                        ForEach(attention) { f in card(f, ai: false) }
                    }
                    if !secondary.isEmpty { passedFold }
                    if !doc.advisory.isEmpty {
                        aiGroupHead
                        ForEach(doc.advisory) { f in card(f, ai: true) }
                    }
                    if !doc.dealTerms.isEmpty { dealTermsPanel }
                    keyTerms
                    Spacer(minLength: 30)
                }
                .padding(.top, 8)
            }
        }
        .background(rl.win)
        .sheet(item: $ws.sourcePageRequest) { req in
            SourcePageView(request: req) { ws.sourcePageRequest = nil }
        }
    }

    private func card(_ f: ReviewFinding, ai: Bool) -> some View {
        FindingCard(f: f, ai: ai, clauseIndex: doc.clauseIndex,
                    sourcePDF: doc.source?.leasePDF, open: ws.selFindingID == f.id)
            .padding(.horizontal, 16)
            .padding(.bottom, 9)
    }

    // MARK: verdict

    private var verdict: some View {
        let v = plainVerdict(doc)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 15) {
                verdictMark(v.level).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(v.eyebrow)
                        .font(rl.ui(12, .semibold)).tracking(0.5).textCase(.uppercase)
                        .foregroundStyle(v.level == .problem ? rl.problem : rl.ok)
                    Text(v.head)
                        .font(rl.serif(27, .medium)).foregroundStyle(rl.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(v.sub)
                        .font(rl.ui(14.5)).foregroundStyle(rl.ink2).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            verdictActions
                .padding(.top, 20)
        }
        .padding(.horizontal, 26)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(rl.line).frame(height: 1) }
    }

    private func verdictMark(_ level: Bucket) -> some View {
        ZStack {
            if level == .problem {
                Circle().fill(rl.problem)
                BucketGlyph(bucket: .problem, size: 16).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(rl.ok, lineWidth: 2)
                BucketGlyph(bucket: .pass, size: 16).foregroundStyle(rl.ok)
            }
        }
        .frame(width: 30, height: 30)
        .padding(.top, 3)
    }

    private var verdictActions: some View {
        HStack(spacing: 10) {
            if passedCount > 0 {
                Button { withAnimation { passOpen = true } } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle().strokeBorder(rl.ok.opacity(0.4), lineWidth: 1.5)
                            RLIcon("check", size: 11).foregroundStyle(rl.ok)
                        }.frame(width: 18, height: 18)
                        Text("\(passedCount) \(passedCount == 1 ? "check passed" : "checks passed")")
                            .font(rl.ui(13, .medium)).foregroundStyle(rl.ink2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if ws.layout == .report {
                ghostButton(icon: "doc", title: "Document") { ws.docOpen = true }
            }
            if doc.source != nil {
                ghostButton(icon: "rerun", title: "Re-check") { ws.recheck() }
            }
            exportButton
        }
    }

    private var exportButton: some View {
        let cleared = ws.allErrorsCleared(doc)
        return Button {
            let written = ExportWriter.save(
                doc: doc,
                reviewer: cleared ? NSFullUserName() : nil,
                dateStamp: cleared ? Date.now.formatted(date: .abbreviated, time: .omitted) : nil)
            if written {
                exported = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { exported = false }
            }
        } label: {
            HStack(spacing: 7) {
                RLIcon(exported ? "check" : "export", size: 14)
                Text(exported ? "Exported" : cleared ? "Approve & export" : "Export")
                    .font(rl.ui(13, .semibold))
            }
            .foregroundStyle(rl.win)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(cleared ? rl.ok : rl.ink, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func ghostButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                RLIcon(icon, size: 14)
                Text(title).font(rl.ui(13, .semibold))
            }
            .foregroundStyle(rl.ink2)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(rl.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(rl.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: group headers

    private func groupHead(_ text: String, color: Color) -> some View {
        Text(text)
            .font(rl.ui(12, .semibold)).tracking(0.5).textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aiGroupHead: some View {
        HStack(spacing: 8) {
            RLIcon("spark", size: 14)
            Text("AI suggestions").font(rl.ui(12, .semibold)).tracking(0.5).textCase(.uppercase)
            Text("· won't block signing").font(rl.ui(12)).foregroundStyle(rl.ink3)
        }
        .foregroundStyle(rl.ai)
        .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: passed fold

    private var passedFold: some View {
        VStack(spacing: 7) {
            Button { withAnimation { passOpen.toggle() } } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(rl.ok.opacity(0.35), lineWidth: 1.5)
                        RLIcon("check", size: 13).foregroundStyle(rl.ok)
                    }.frame(width: 22, height: 22)
                    Text(passedLabel).font(rl.ui(14, .semibold)).foregroundStyle(rl.ink)
                    Spacer()
                    RLIcon("chev", size: 15).foregroundStyle(rl.ink4)
                        .rotationEffect(.degrees(passOpen ? 90 : 0))
                }
                .padding(.horizontal, 15).padding(.vertical, 13)
                .background(rl.surface2, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(rl.line, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if passOpen {
                VStack(spacing: 0) {
                    ForEach(secondary) { f in passedItem(f) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var passedLabel: String {
        let notRun = secondary.count - passedCount
        let base = "\(passedCount) \(passedCount == 1 ? "check passed" : "checks passed")"
        return notRun > 0 ? base + " · \(notRun) not run" : base
    }

    private func passedItem(_ f: ReviewFinding) -> some View {
        Button {
            if let ev = f.evidence.first { ws.jumpClause(ev.clause) }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(rl.color(f.bucket).opacity(0.32), lineWidth: 1.5)
                    BucketGlyph(bucket: f.bucket, size: 12).foregroundStyle(rl.color(f.bucket))
                }.frame(width: 18, height: 18)
                .accessibilityHidden(true)
                Text(f.headline).font(rl.ui(13.5, .medium)).foregroundStyle(rl.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(f.severity.shortLabel).font(rl.ui(12.5)).foregroundStyle(rl.ink3)
            }
            .padding(.horizontal, 15).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: deal terms

    private var dealTermsPanel: some View {
        let verified = doc.dealTerms.filter { $0.verified }.count
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                RLIcon("tablecells", size: 13).foregroundStyle(rl.ink3)
                Text("Deal terms — \(verified) of \(doc.dealTerms.count) verified")
                    .font(rl.ui(12, .semibold)).tracking(0.5).textCase(.uppercase)
                    .foregroundStyle(rl.ink3)
                Spacer()
            }
            .padding(.top, 18)

            VStack(spacing: 0) {
                ForEach(Array(doc.dealTerms.enumerated()), id: \.element.id) { idx, term in
                    HStack(spacing: 10) {
                        BucketGlyph(bucket: term.verified ? .ok : .problem, size: 18)
                            .foregroundStyle(rl.color(term.verified ? .ok : .problem))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.label).font(rl.ui(13.5, .semibold)).foregroundStyle(rl.ink)
                            Text(term.verified
                                 ? "Matches the lease — \(term.expected)"
                                 : "Mismatch — expected \(term.expected)\(term.actual.map { ", lease shows \($0)" } ?? "")")
                                .font(rl.ui(12)).foregroundStyle(rl.ink2)
                        }
                        Spacer(minLength: 10)
                        Text(term.source == "thread" ? "from thread" : "from deal sheet")
                            .font(rl.mono(10)).foregroundStyle(rl.ink3)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(rl.surface2, in: Capsule())
                    }
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    if idx < doc.dealTerms.count - 1 { Divider().overlay(rl.line) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(rl.line, lineWidth: 1))
            .padding(.top, 11)
        }
        .padding(.horizontal, 16)
    }

    // MARK: key terms

    private var keyTerms: some View {
        VStack(spacing: 0) {
            Button { withAnimation { termsOpen.toggle() } } label: {
                HStack(spacing: 9) {
                    RLIcon("chev", size: 13).foregroundStyle(rl.ink3)
                        .rotationEffect(.degrees(termsOpen ? 90 : 0))
                    Text("Key terms").font(rl.ui(12, .semibold)).tracking(0.5).textCase(.uppercase)
                        .foregroundStyle(rl.ink3)
                    Spacer()
                    HStack(spacing: 4) {
                        RLIcon("spark", size: 10)
                        Text("Read by AI").font(rl.mono(10))
                    }
                    .foregroundStyle(rl.ai)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(rl.aiSoft, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 18)

            if termsOpen {
                VStack(spacing: 0) {
                    ForEach(Array(doc.facts.enumerated()), id: \.element.id) { idx, term in
                        HStack {
                            Text(term.k).font(rl.ui(13)).foregroundStyle(rl.ink2)
                            Spacer(minLength: 14)
                            Text(term.v).font(rl.ui(13.5, .semibold))
                                .foregroundStyle(term.flag ? rl.accent : rl.ink)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        if idx < doc.facts.count - 1 { Divider().overlay(rl.line) }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(rl.line, lineWidth: 1))
                .padding(.top, 11)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Finding card

private struct FindingCard: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    let f: ReviewFinding
    let ai: Bool
    let clauseIndex: [String: (num: String, page: Int)]
    let sourcePDF: URL?
    let open: Bool
    @State private var hover = false
    @FocusState private var noteFocused: Bool

    private var bucket: Bucket { ai ? .ai : f.bucket }

    /// Spoken severity word for the header summary — the color + `mark` glyph are the only
    /// other carriers of severity, and the glyph is hidden from VoiceOver.
    private var severityWord: String {
        switch bucket {
        case .problem: "Problem"
        case .warn: "Heads-up"
        case .ai: "AI suggestion"
        default: "Note"
        }
    }

    /// One-line summary the card's header button speaks: severity, title, reviewed state,
    /// and whether it's currently expanded.
    private var headerLabel: String {
        var parts = ["\(severityWord): \(f.headline)"]
        if ws.isReviewed(f.id) { parts.append("reviewed") }
        parts.append(open ? "expanded" : "collapsed")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if open { body_.transition(.opacity) }
        }
        .background(rl.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(open || hover ? rl.line2 : rl.line, lineWidth: 1)
        )
        .shadow(color: open ? rl.shadowColor.opacity(0.35)
                            : (hover ? rl.shadowColor.opacity(0.14) : .clear),
                radius: open ? 12 : (hover ? 7 : 0), x: 0, y: open ? 8 : 4)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.18), value: hover)
        .animation(.easeOut(duration: 0.22), value: open)
        // INTERACTIVE container: must NOT .combine (that would hide the toggle, source-page,
        // mark-reviewed, note, and evidence controls). .contain keeps it a navigable group
        // whose children remain individually accessible.
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        Button { ws.selectFinding(open ? nil : f.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                mark.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(f.headline).font(rl.ui(15, .semibold)).foregroundStyle(rl.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if f.expected != nil { fixPreview.padding(.top, 11) }
                    else if let loc = locationText { fixLocation(loc).padding(.top, 7) }
                }
                if ws.isReviewed(f.id) {
                    HStack(spacing: 5) {
                        RLIcon("check", size: 12); Text("Reviewed").font(rl.ui(11.5, .semibold))
                    }
                    .foregroundStyle(rl.ok).padding(.top, 2)
                }
                RLIcon("chev", size: 16).foregroundStyle(rl.ink4)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The header is the card's summary. Severity lives only in the (hidden) mark glyph's
        // color, so fold it into an explicit label along with the title, reviewed state, and
        // expand/collapse state. Child controls below stay individually navigable via .contain.
        .accessibilityLabel(headerLabel)
        .accessibilityHint(open ? "Double-tap to collapse" : "Double-tap to expand")
    }

    private var mark: some View {
        ZStack {
            switch bucket {
            case .problem:
                RoundedRectangle(cornerRadius: 7).fill(rl.problem)
                BucketGlyph(bucket: .problem, size: 13).foregroundStyle(.white)
            case .warn:
                RoundedRectangle(cornerRadius: 7).fill(rl.warn)
                BucketGlyph(bucket: .warn, size: 13).foregroundStyle(.white)
            case .ai:
                RoundedRectangle(cornerRadius: 7).strokeBorder(rl.ai.opacity(0.35), lineWidth: 1.5)
                BucketGlyph(bucket: .ai, size: 13).foregroundStyle(rl.ai)
            default:
                RoundedRectangle(cornerRadius: 7).strokeBorder(rl.note.opacity(0.35), lineWidth: 1.5)
                BucketGlyph(bucket: .note, size: 13).foregroundStyle(rl.note)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 1)
    }

    private var fixPreview: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("In the document").font(rl.ui(10.5, .semibold)).tracking(0.3)
                    .textCase(.uppercase).foregroundStyle(rl.ink3)
                Text(f.actual ?? "").font(rl.mono(14, .semibold)).foregroundStyle(rl.problem)
            }
            RLIcon("arrow", size: 16).foregroundStyle(rl.ink4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Should be").font(rl.ui(10.5, .semibold)).tracking(0.3)
                    .textCase(.uppercase).foregroundStyle(rl.ink3)
                Text(f.expected ?? "").font(rl.mono(14, .semibold)).foregroundStyle(rl.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(rl.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    private var locationText: String? {
        guard let clause = f.firstClause, let loc = clauseIndex[clause] else { return nil }
        return "§\(loc.num) · page \(loc.page)"
    }

    private var citedPage: Int? { f.firstClause.flatMap { clauseIndex[$0]?.page } }

    private func fixLocation(_ text: String) -> some View {
        HStack(spacing: 5) {
            RLIcon("jump", size: 11)
            Text(text).font(rl.mono(11, .medium))
        }
        .foregroundStyle(rl.ink3)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(f.detail).font(rl.ui(14)).foregroundStyle(rl.ink2).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            if !f.evidence.isEmpty {
                VStack(spacing: 6) {
                    ForEach(f.evidence) { e in
                        EvidenceRowView(e: e, loc: clauseIndex[e.clause])
                    }
                }
                .padding(.top, 13)
            }
            if let pdf = sourcePDF, let page = citedPage {
                Button { ws.openSourcePage(pdf, page: page) } label: {
                    HStack(spacing: 5) {
                        RLIcon("doc", size: 11)
                        Text("Open source page \(page)").font(rl.mono(11, .medium))
                    }
                    .foregroundStyle(rl.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            if !ai { reviewControls.padding(.top, 14) }
        }
        .padding(.leading, 50).padding(.trailing, 16).padding(.bottom, 17).padding(.top, 2)
    }

    private var reviewControls: some View {
        HStack(spacing: 11) {
            Button { ws.toggleReviewed(f.id) } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ws.isReviewed(f.id) ? rl.ok : Color.clear)
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(ws.isReviewed(f.id) ? rl.ok : rl.line2, lineWidth: 1.5)
                        if ws.isReviewed(f.id) {
                            RLIcon("check", size: 12).foregroundStyle(.white)
                        }
                    }.frame(width: 18, height: 18)
                    Text("Mark reviewed").font(rl.ui(13)).foregroundStyle(rl.ink2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Checkbox-style: the label text is static, so convey the checked state as a trait.
            .accessibilityAddTraits(ws.isReviewed(f.id) ? .isSelected : [])

            TextField("Add a note…", text: Binding(
                get: { ws.note(f.id) },
                set: { ws.setNote(f.id, $0) }
            ))
            .textFieldStyle(.plain)
            .focused($noteFocused)
            .font(rl.ui(13)).foregroundStyle(rl.ink)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(rl.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(noteFocused ? rl.accent : rl.line, lineWidth: noteFocused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.15), value: noteFocused)
        }
    }
}

// MARK: - Evidence row (own view for hover state)

/// One cited quote inside an expanded finding. Clicking it jumps the document to the
/// clause; hovering lifts it onto a faint surface, matching the design's evidence cards.
private struct EvidenceRowView: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    let e: ReviewEvidence
    let loc: (num: String, page: Int)?
    @State private var hover = false

    var body: some View {
        Button { ws.jumpClause(e.clause) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    RLIcon("jump", size: 12)
                    Text("§\(loc?.num ?? "?") · page \(loc?.page ?? 0) — show in document")
                        .font(rl.mono(11, .semibold))
                }
                .foregroundStyle(rl.accent)
                Text("“\(e.quote)”").font(rl.serif(13.5)).italic()
                    .foregroundStyle(rl.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? rl.surface2 : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(hover ? rl.line2 : rl.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
