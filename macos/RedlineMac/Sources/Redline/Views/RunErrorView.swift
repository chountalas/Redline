import AppKit
import SwiftUI

/// First-class run-failure state (G7-UI / G8). Replaces the old bare `.alert`: a dimmed
/// backdrop + centered card carrying the plain-language guidance, a Retry that re-opens the
/// run sheet with the prior inputs intact, Copy details, and the raw message behind a
/// disclosure. Scanned PDFs get a distinct headline + icon. Matches CheckingOverlayView's
/// overlay/card visual language.
struct RunErrorView: View {
    let failure: RunFailure
    @Environment(Workspace.self) private var ws
    @Environment(\.rl) private var rl
    @State private var detailsOpen = false

    var body: some View {
        ZStack {
            // Backdrop intentionally swallows clicks to the workspace beneath while the error shows.
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            card
                .frame(maxWidth: 460)
                .padding(24)
                .background(rl.win, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(rl.line2, lineWidth: 1))
                .shadow(color: rl.shadowColor, radius: 30, y: 12)
                .padding(40)
        }
    }

    // MARK: card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RLIcon(iconName, size: 18).foregroundStyle(iconTint)
                    .frame(width: 34, height: 34)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 10))
                Text(headline)
                    .font(rl.serif(22, .medium)).foregroundStyle(rl.ink)
                Spacer(minLength: 0)
            }

            Text(failure.guidance)
                .font(rl.ui(13.5)).foregroundStyle(rl.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            disclosure.padding(.top, 16)

            actions.padding(.top, 20)
        }
    }

    // MARK: details disclosure

    private var disclosure: some View {
        DisclosureGroup("Details", isExpanded: $detailsOpen) {
            ScrollView {
                Text(failure.raw)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(rl.ink2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 140)
            .background(rl.surface2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(rl.line, lineWidth: 1))
            .padding(.top, 8)
        }
        .font(rl.ui(12.5, .medium))
        .tint(rl.ink3)
    }

    // MARK: actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button { ws.dismissFailure() } label: {
                Text("Dismiss").font(rl.ui(13, .medium)).foregroundStyle(rl.ink2)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(rl.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(rl.line2, lineWidth: 1))
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)

            Button { copyDetails() } label: {
                HStack(spacing: 6) {
                    RLIcon("export", size: 12)
                    Text("Copy details").font(rl.ui(13, .medium))
                }
                .foregroundStyle(rl.ink2)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(rl.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(rl.line2, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { ws.retryAfterFailure() } label: {
                HStack(spacing: 7) {
                    RLIcon("rerun", size: 12)
                    Text("Retry").font(rl.ui(13, .semibold))
                }
                .foregroundStyle(rl.win)
                .padding(.horizontal, 15).padding(.vertical, 8)
                .background(rl.ink, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
        }
    }

    private func copyDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failure.raw, forType: .string)
    }

    // MARK: scanned vs generic presentation

    private var isScanned: Bool {
        if case .scannedPDF = failure.cause { return true } else { return false }
    }

    private var headline: String {
        isScanned ? "This PDF is a scan" : "Check couldn't finish"
    }

    private var iconName: String {
        // "search" → magnifyingglass (viewfinder-adjacent) for the scan; "alert" (△) otherwise.
        isScanned ? "search" : "alert"
    }

    private var iconTint: Color { isScanned ? rl.ai : rl.problem }
    private var iconBackground: Color { isScanned ? rl.aiSoft : rl.problemSoft }
}
