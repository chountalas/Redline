import SwiftUI

/// Brand lockup: the accent square + "Redline".
struct BrandMark: View {
    @Environment(\.rl) private var rl
    var size: CGFloat = 16
    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 5).fill(rl.accent).frame(width: 15, height: 15)
                .accessibilityHidden(true)
            Text("Redline").font(rl.ui(size, .bold)).tracking(-0.2).foregroundStyle(rl.ink)
        }
    }
}

private func statusBucket(_ doc: ReviewDoc) -> Bucket { docStatus(doc).bucket }

/// A document's status dot — red/amber fill for problems/heads-up, a green ring for clean.
struct StatusDot: View {
    @Environment(\.rl) private var rl
    let bucket: Bucket
    var size: CGFloat = 9
    var body: some View {
        Group {
            if bucket == .ok {
                Circle().strokeBorder(rl.ok, lineWidth: 1.5)
            } else {
                Circle().fill(rl.color(bucket))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Library rail (focused layout)

struct LibraryRail: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    @FocusState private var searchFocused: Bool

    private func matches(_ d: ReviewDoc, _ q: String) -> Bool {
        q.isEmpty || d.name.lowercased().contains(q)
            || d.kind.lowercased().contains(q) || d.party.lowercased().contains(q)
    }

    var body: some View {
        @Bindable var ws = ws
        let q = ws.query.trimmingCharacters(in: .whitespaces).lowercased()
        return VStack(spacing: 0) {
            HStack {
                BrandMark(size: 16)
                Spacer()
                HomeButton()
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)

            HStack(spacing: 8) {
                RLIcon("search", size: 15).foregroundStyle(searchFocused ? rl.accent : rl.ink3)
                TextField("Search documents", text: $ws.query)
                    .textFieldStyle(.plain).font(rl.ui(13)).foregroundStyle(rl.ink)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(rl.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(searchFocused ? rl.accent : rl.line, lineWidth: searchFocused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.15), value: searchFocused)
            .padding(.horizontal, 14).padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(docListSections(documents: ws.documents, groups: ws.groups)) { group in
                        let items = group.documents.filter { matches($0, q) }
                        if !items.isEmpty {
                            Text(group.label)
                                .font(rl.ui(11, .semibold)).tracking(0.6).textCase(.uppercase)
                                .foregroundStyle(rl.ink3)
                                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 7)
                            ForEach(items) { d in DocRow(d: d) }
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            Divider().overlay(rl.line)
            HStack(spacing: 8) {
                RLIcon("spark", size: 13)
                Text("AI reads · the checks decide").font(rl.ui(11.5))
            }
            .foregroundStyle(rl.ink3)
            .padding(.horizontal, 18).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 212)
        .background(rl.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(rl.line).frame(width: 1) }
    }

}

// MARK: - Doc row (own view for hover state)

/// A single document in the library rail. Active is the full surface chip with a hairline
/// border; hover lifts it onto a faint half-surface wash so the row reads as clickable.
private struct DocRow: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    let d: ReviewDoc
    @State private var hover = false

    var body: some View {
        let active = d.id == ws.selectedDocID
        let st = docStatus(d)
        return Button { ws.selectDoc(d.id) } label: {
            HStack(spacing: 11) {
                StatusDot(bucket: st.bucket)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.name).font(rl.ui(13.5, .medium)).foregroundStyle(rl.ink)
                        .lineLimit(1)
                    Text(d.kind).font(rl.ui(12)).foregroundStyle(rl.ink3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(active ? rl.surface : (hover ? rl.surface.opacity(0.5) : .clear),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 10).stroke(rl.line2, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        // Single button, no interactive children. The StatusDot is color-only, and the row
        // shows no status text, so combine alone would not speak status — add it explicitly.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(d.name), \(d.kind), \(st.word)")
        .contextMenu { DocumentActionsMenu(doc: d) }
    }
}

// MARK: - Doc switcher (header dropdown for split / report layouts)

struct DocSwitcher: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    @State private var open = false

    @ViewBuilder var body: some View {
        // The switcher only renders inside the workspace, which routes to Home when the library
        // is empty — so `currentDoc` is non-nil here; guard rather than force-unwrap (G11).
        if let cur = ws.currentDoc {
            switcher(cur)
        }
    }

    private func switcher(_ cur: ReviewDoc) -> some View {
        let st = docStatus(cur)
        return Button { open.toggle() } label: {
            HStack(spacing: 10) {
                StatusDot(bucket: st.bucket)
                Text(cur.name).font(rl.ui(13.5, .semibold)).foregroundStyle(rl.ink).lineLimit(1)
                RLIcon("chevd", size: 15).foregroundStyle(rl.ink3)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .frame(minWidth: 230, alignment: .leading)
            .background(rl.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(rl.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Trigger shows a color-only StatusDot + name with no status text — fold the status
        // word in so VoiceOver speaks the current document's state.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cur.name), \(st.word)")
        .accessibilityHint("Switch document")
        .popover(isPresented: $open, arrowEdge: .bottom) { menu }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(docListSections(documents: ws.documents, groups: ws.groups)) { group in
                Text(group.label)
                    .font(rl.ui(10.5, .semibold)).tracking(0.6).textCase(.uppercase)
                    .foregroundStyle(rl.ink3)
                    .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 5)
                ForEach(group.documents) { d in
                    let s = docStatus(d)
                    Button { ws.selectDoc(d.id); open = false } label: {
                        HStack(spacing: 11) {
                            StatusDot(bucket: s.bucket)
                            Text(d.name).font(rl.ui(13.5, .medium)).foregroundStyle(rl.ink)
                            Spacer(minLength: 14)
                            Text(s.word).font(rl.ui(12)).foregroundStyle(rl.ink3)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(d.id == ws.selectedDocID ? rl.surface2 : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(d.name), \(s.word)")
                    .accessibilityAddTraits(d.id == ws.selectedDocID ? .isSelected : [])
                    .contextMenu { DocumentActionsMenu(doc: d) }
                }
            }
            Divider().overlay(rl.line).padding(.vertical, 5)
            Button { ws.openRunSheet(); open = false } label: {
                HStack(spacing: 11) {
                    RLIcon("plus", size: 14).foregroundStyle(rl.accent).frame(width: 9)
                    Text("Review a new PDF…").font(rl.ui(13.5, .medium)).foregroundStyle(rl.ink)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ws.isRunning)
        }
        .frame(width: 300)
        .padding(6)
        .background(rl.surface)
    }
}
