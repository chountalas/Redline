import SwiftUI

/// First-run / empty-library state. Shown by `WorkspaceView` whenever there are no
/// documents — the app opens here instead of into pre-loaded demo data. One primary
/// action (check a document); examples load on demand for a demo.
struct EmptyStateView: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BrandMark(size: 23)

            Text("Catch document issues before approval.")
                .font(rl.serif(20, .medium)).foregroundStyle(rl.ink2)
                .padding(.top, 14)

            primaryButton.padding(.top, 26)

            HStack(spacing: 6) {
                Text("No documents yet").font(rl.ui(12.5)).foregroundStyle(rl.ink3)
                Text("·").font(rl.ui(12.5)).foregroundStyle(rl.ink4)
                Button { ws.loadExamples() } label: {
                    HStack(spacing: 4) {
                        Text("Load examples").font(rl.ui(12.5, .medium))
                        RLIcon("chev", size: 11)
                    }
                    .foregroundStyle(rl.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(rl.win)
    }

    private var primaryButton: some View {
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
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
