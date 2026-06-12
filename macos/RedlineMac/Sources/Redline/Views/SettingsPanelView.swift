import SwiftUI

/// Settings panel — the native replacement for the design-host "Tweaks" panel. Now also
/// houses the persistent **AI** config (provider / model / key / base-URL) that used to be
/// re-collected in every run modal. Plus the prototype's four controls: layout, dark mode,
/// accent, document text size. Accent stays decoupled from semantic error-red.
struct SettingsPanelView: View {
    @Environment(\.rl) private var rl
    @Bindable var ws: Workspace

    private let accents = ["#c8302b", "#a8211c", "#b4531d", "#2f5fb0"]

    /// Human-readable name for each accent hex, so VoiceOver speaks "Red accent" instead of
    /// the raw hex. Keyed by lowercased hex so it's order-independent.
    private func accentName(_ hex: String) -> String {
        switch hex.lowercased() {
        case "#c8302b": "Red"
        case "#a8211c": "Crimson"
        case "#b4531d": "Rust"
        case "#2f5fb0": "Blue"
        default: "Accent"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AISettingsSection(ws: ws)

            Divider().overlay(rl.line)

            section("Layout")
            Picker("", selection: $ws.layout) {
                ForEach(RLLayout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            section("Theme")
            Toggle(isOn: $ws.isDark) {
                Text("Dark mode").font(rl.ui(13)).foregroundStyle(rl.ink)
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 7) {
                Text("Accent").font(rl.ui(13)).foregroundStyle(rl.ink2)
                HStack(spacing: 8) {
                    ForEach(accents, id: \.self) { hex in
                        let on = hex.lowercased() == ws.accentHex.lowercased()
                        Button { ws.accentHex = hex } label: {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: hex))
                                .frame(height: 30)
                                .overlay {
                                    if on {
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(rl.ink, lineWidth: 2)
                                        RLIcon("check", size: 12).foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(accentName(hex)) accent")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }

            section("Reading")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Document text").font(rl.ui(13)).foregroundStyle(rl.ink2)
                    Spacer()
                    Text("\(Int(ws.docSize))px").font(rl.mono(12)).foregroundStyle(rl.ink3)
                }
                Slider(value: $ws.docSize, in: 14...20, step: 1)
            }
        }
        .frame(width: 264)
        .padding(16)
        .background(rl.surface)
    }

    private func section(_ title: String) -> some View { SettingsSectionLabel(title) }
}

/// The persistent provider config. Extracted so the run modal's chip popover and the full
/// settings panel render the exact same controls against the one workspace store.
struct AISettingsSection: View {
    @Environment(\.rl) private var rl
    @Bindable var ws: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SettingsSectionLabel("AI")

            HStack {
                Text("Profile").font(rl.ui(13)).foregroundStyle(rl.ink2)
                Spacer()
                Picker("", selection: $ws.profile) {
                    ForEach(ReviewProfile.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            Text(ws.profile.detail)
                .font(rl.ui(11.5))
                .foregroundStyle(rl.ink3)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Provider").font(rl.ui(13)).foregroundStyle(rl.ink2)
                Spacer()
                Picker("", selection: Binding(
                    get: { ws.provider },
                    set: { ws.selectProvider($0) }
                )) {
                    ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            field("Model", text: $ws.model,
                  placeholder: ws.provider.modelPlaceholder)

            if ws.provider == .openai || ws.provider == .anthropic {
                field("API key", text: $ws.apiKey, placeholder: ws.provider.apiKeyPlaceholder, secure: true)
            }
            if ws.provider == .ollama {
                field("Base URL", text: $ws.baseURL, placeholder: "http://localhost:11434")
            }
        }
        .animation(.easeOut(duration: 0.16), value: ws.provider)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>,
                       placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(rl.ui(12)).foregroundStyle(rl.ink2)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain).font(rl.ui(13)).foregroundStyle(rl.ink)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(rl.surface2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(rl.line2, lineWidth: 1))
        }
    }
}

/// Shared uppercase section eyebrow used across the settings panel.
struct SettingsSectionLabel: View {
    @Environment(\.rl) private var rl
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(rl.ui(10.5, .semibold)).tracking(0.6).textCase(.uppercase)
            .foregroundStyle(rl.ink3)
    }
}

/// Native window-toolbar button that toggles the in-window settings panel. `ws` is passed in
/// explicitly because toolbar content is hosted in a detached environment branch that
/// does not inherit the body's `.environment(ws)` — reading it via @Environment would trap.
struct SettingsButton: View {
    let ws: Workspace

    var body: some View {
        Button { ws.showSettingsPanel.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

/// Native window-toolbar button that opens the run sheet. `ws` is passed in for the same
/// reason as `SettingsButton` — the window toolbar doesn't inherit the body environment.
struct AddDocButton: View {
    let ws: Workspace

    var body: some View {
        Button {
            ws.openRunSheet()
        } label: {
            Image(systemName: "plus")
        }
        .disabled(ws.isRunning)
        .help("Review a new PDF")
        .accessibilityLabel("Review a new PDF")
    }
}
