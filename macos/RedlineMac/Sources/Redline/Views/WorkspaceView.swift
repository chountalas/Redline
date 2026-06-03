import SwiftUI

/// The three-pane workspace shell. One "Layout" choice arranges the same panes three ways:
///   • focused — library rail · report · document
///   • split   — header switcher · report · document (the default)
///   • report  — a single memo column; the document slides in on demand
struct WorkspaceView: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Normally only reached with a document selected — the home screen gates entry and owns
        // the empty-library invite. If the library is empty (no `currentDoc`), fall back to Home
        // rather than force a pane (G11).
        if let doc = ws.currentDoc {
            loadedBody(doc)
        } else {
            HomeView()
        }
    }

    private func loadedBody(_ doc: ReviewDoc) -> some View {
        ZStack {
            VStack(spacing: 0) {
                if ws.layout != .focused { appHeader(doc) }
                HStack(spacing: 0) {
                    if ws.layout == .focused { LibraryRail() }
                    center(doc)
                    if ws.layout != .report {
                        DocumentPaneView(doc: doc)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            if ws.layout == .report && ws.docOpen {
                reportOverlay(doc)
            }
        }
        .background(rl.win)
        .animation(.easeOut(duration: 0.2), value: ws.docOpen)
    }

    // MARK: header (split / report)

    private func appHeader(_ doc: ReviewDoc) -> some View {
        HStack(spacing: 14) {
            HomeButton()
            Rectangle().fill(rl.line).frame(width: 1, height: 18)
            DocSwitcher()
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(rl.win)
        .overlay(alignment: .bottom) { Rectangle().fill(rl.line).frame(height: 1) }
    }

    // MARK: center (report or re-check overlay)

    @ViewBuilder
    private func center(_ doc: ReviewDoc) -> some View {
        let content = Group {
            if ws.checking {
                CheckingOverlayView(doc: doc, step: ws.checkStep, onCancel: ws.cancelRun)
            } else {
                ReportPaneView(doc: doc)
            }
        }
        switch ws.layout {
        case .focused:
            content.frame(width: 408)
                .overlay(alignment: .trailing) { Rectangle().fill(rl.line).frame(width: 1) }
        case .split:
            content.frame(width: 508)
                .overlay(alignment: .trailing) { Rectangle().fill(rl.line).frame(width: 1) }
        case .report:
            content
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: report-layout slide-over document

    private func reportOverlay(_ doc: ReviewDoc) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(ws.isDark ? 0.5 : 0.32)
                .ignoresSafeArea()
                .onTapGesture { ws.docOpen = false }
                .transition(.opacity)
            DocumentPaneView(doc: doc, onClose: { ws.docOpen = false })
                .frame(width: 600)
                .frame(maxHeight: .infinity)
                .background(rl.docBG)
                .overlay(alignment: .leading) { Rectangle().fill(rl.line2).frame(width: 1) }
                .shadow(color: rl.shadowColor.opacity(0.5), radius: 30, x: -12, y: 0)
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
        }
    }
}
