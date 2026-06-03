import SwiftUI

/// App root: owns the workspace store, injects the resolved theme, and hosts the
/// three-pane v2 workspace plus the run sheet and the run-error overlay. ⌘R opens the run sheet.
struct ContentView: View {
    @State private var ws = Workspace()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var ws = ws
        rootScreen
            .environment(ws)
            .environment(\.rl, ws.theme)
            .preferredColorScheme(ws.isDark ? .dark : .light)
            .frame(minWidth: 1040, minHeight: 680)
            .background(ws.theme.win)
            .background(WindowConfigurator(background: ws.theme.win, isDark: ws.isDark))
            .navigationTitle("Redline")
            .navigationSubtitle("Document Review")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    AddDocButton(ws: ws)
                    SettingsButton(ws: ws)
                }
            }
            .overlay(alignment: .topTrailing) {
                settingsOverlay
            }
            .overlay {
                if let failure = ws.run.failure {
                    RunErrorView(failure: failure)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: ws.run.failure != nil)
            .sheet(isPresented: $ws.showRunSheet) {
                RunSheet()
                    .environment(ws)
                    .environment(\.rl, ws.theme)
            }
            .onReceive(NotificationCenter.default.publisher(for: .runRedlineCheck)) { _ in
                if !ws.isRunning { ws.openRunSheet() }
            }
    }

    /// Home dashboard or the three-pane workspace, chosen by the current screen mode.
    @ViewBuilder private var rootScreen: some View {
        if ws.screen == .home {
            HomeView()
        } else {
            WorkspaceView()
        }
    }

    @ViewBuilder private var settingsOverlay: some View {
        if ws.showSettingsPanel {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { ws.showSettingsPanel = false }

                SettingsPanelView(ws: ws)
                    .environment(\.rl, ws.theme)
                    .background(ws.theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(ws.theme.line2, lineWidth: 1))
                    .shadow(color: ws.theme.shadowColor.opacity(0.32), radius: 24, y: 10)
                    .padding(.top, 12)
                    .padding(.trailing, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
