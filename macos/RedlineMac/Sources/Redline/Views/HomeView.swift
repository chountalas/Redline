import SwiftUI

/// The app's landing surface — one Home that scales with the library:
///   • a run in progress  → the pipeline progress animation (a check started from here runs
///     while the library may still be empty, so it can't read `currentDoc`)
///   • an empty library    → the first-run invite (`EmptyStateView`)
///   • documents present   → a dashboard of status cards, grouped like the library rail
/// Selecting a card enters the three-pane workspace; the workspace's Home button returns here.
struct HomeView: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws

    var body: some View {
        if ws.checking {
            CheckingOverlayView(doc: nil, step: ws.checkStep, onCancel: ws.cancelRun)
        } else if ws.documents.isEmpty {
            EmptyStateView()
        } else {
            dashboard
        }
    }

    // MARK: populated dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    BrandMark(size: 18)
                    Spacer()
                }
                greeting
                CheckDocumentButton()
                ForEach(docListSections(documents: ws.documents, groups: ws.groups)) { group in
                    section(group.label, group.documents)
                }
                footer
            }
            .frame(maxWidth: 940, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 46)
            .frame(maxWidth: .infinity)
        }
        .background(rl.win)
    }

    private var greeting: some View {
        let total = ws.documents.count
        let attention = ws.documents.filter { docStatus($0).bucket != .ok }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(attention == 0 ? "Everything’s clear"
                 : attention == 1 ? "1 document needs attention"
                                  : "\(attention) documents need attention")
                .font(rl.serif(28, .medium)).foregroundStyle(rl.ink)
            Text(attention == 0
                 ? "\(total) \(total == 1 ? "document" : "documents") · all checks passing"
                 : "\(total) \(total == 1 ? "document" : "documents") in your library")
                .font(rl.ui(14)).foregroundStyle(rl.ink3)
        }
    }

    private func section(_ label: String, _ items: [ReviewDoc]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(rl.ui(11.5, .semibold)).tracking(0.6).textCase(.uppercase)
                .foregroundStyle(rl.ink3)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230, maximum: .infinity), spacing: 14)],
                alignment: .leading, spacing: 14
            ) {
                ForEach(items) { HomeDocCard(d: $0) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            RLIcon("spark", size: 13)
            Text("AI reads · the checks decide").font(rl.ui(12))
        }
        .foregroundStyle(rl.ink3)
        .padding(.top, 4)
    }
}

// MARK: - Primary action

/// "Check a document" — the same ink-filled treatment as the first-run invite, so the empty and
/// populated home states read as one surface. Opens the run sheet (the document drop target).
private struct CheckDocumentButton: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        Button { ws.openRunSheet() } label: {
            HStack(spacing: 9) {
                RLIcon("tray", size: 15)
                Text("Check a document").font(rl.ui(14, .semibold))
            }
            .foregroundStyle(rl.win)
            .padding(.horizontal, 20).padding(.vertical, 11)
            .background(rl.ink, in: RoundedRectangle(cornerRadius: 11))
            .scaleEffect(hover && !reduceMotion ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .disabled(ws.isRunning)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Document card

/// A library document on the home grid. The whole card enters the workspace; hover lifts it
/// with a hairline + soft shadow, matching the rail rows. Status is derived live via docStatus.
private struct HomeDocCard: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    let d: ReviewDoc
    @State private var hover = false

    var body: some View {
        let st = docStatus(d)
        return Button { ws.selectDoc(d.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(d.kind).font(rl.ui(12)).foregroundStyle(rl.ink3).lineLimit(1)
                    Spacer(minLength: 8)
                    RLIcon("arrow", size: 13).foregroundStyle(rl.ink4).opacity(hover ? 1 : 0)
                        .accessibilityHidden(true)
                }
                Text(d.name)
                    .font(rl.ui(16, .semibold)).foregroundStyle(rl.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    StatusDot(bucket: st.bucket)
                    Text(st.word).font(rl.ui(12.5, .medium)).foregroundStyle(rl.color(st.bucket))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .padding(16)
            .background(rl.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(hover ? rl.line2 : rl.line, lineWidth: 1))
            .shadow(color: hover ? rl.shadowColor.opacity(0.16) : .clear, radius: 10, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        // One VoiceOver element: the whole card is a single button with no interactive
        // children. The StatusDot encodes status by color only, so fold the status word
        // (from docStatus) into the label or it would be silent.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(d.kind), \(d.name), \(st.word)")
        .contextMenu { DocumentActionsMenu(doc: d) }
    }
}

// MARK: - Home button (shared nav control)

/// Returns to the home dashboard. Used in the workspace header (split/report layouts) and at
/// the top of the library rail (focused layout).
struct HomeButton: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    @State private var hover = false

    var body: some View {
        Button { ws.goHome() } label: {
            HStack(spacing: 5) {
                RLIcon("chevl", size: 13)
                Text("Home").font(rl.ui(13.5, .medium))
            }
            .foregroundStyle(hover ? rl.ink : rl.ink2)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(hover ? rl.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
