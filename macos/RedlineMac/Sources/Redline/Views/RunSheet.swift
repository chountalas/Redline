import SwiftUI
import UniformTypeIdentifiers

/// Collects the inputs for a real engine run and hands them to the workspace, which drives
/// the re-check animation and adapts the result into a reviewable document.
///
/// v2: document-first. The modal only asks "what do you want to check" — the lease PDF is
/// the hero, with a deal sheet and focus note as quiet, expandable extras. Provider / model
/// / key live in Settings now (the chip below reflects them, read-only), so the run modal
/// stays about the document instead of mirroring CLI flags.
struct RunSheet: View {
    @Environment(\.rl) private var rl
    @Environment(Workspace.self) private var ws

    @State private var leasePDF: URL?
    @State private var dealSheet: URL?
    @State private var context = ""
    @State private var thread = ""
    @State private var pdfImporter = false
    @State private var dealImporter = false
    @State private var focusOpen = false
    @State private var dropTargeted = false
    @State private var threadDropTargeted = false
    @State private var providerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            dropZone
            dealContextSection
            dealRow
            focusRow
            Divider().overlay(rl.line).padding(.vertical, 2)
            providerChip
            footer.padding(.top, 2)
        }
        .padding(22)
        .frame(width: 460)
        .background(rl.win)
        .fileImporter(isPresented: $pdfImporter, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { leasePDF = url }
        }
        .fileImporter(isPresented: $dealImporter, allowedContentTypes: [.yaml, .data]) { result in
            if case .success(let url) = result { dealSheet = url }
        }
        .onAppear {
            if let s = ws.pendingRetry {
                leasePDF = s.leasePDF
                dealSheet = s.dealSheet
                context = s.context
                thread = s.thread
                ws.pendingRetry = nil   // consume — normal opens stay fresh
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 15)
            Text("Check a lease").font(rl.ui(14)).foregroundStyle(rl.ink3)
            Spacer()
        }
    }

    // MARK: drop zone (hero when empty, compact card once chosen)

    @ViewBuilder private var dropZone: some View {
        if let url = leasePDF {
            selectedFileCard(url)
        } else {
            emptyDropZone
        }
    }

    private var emptyDropZone: some View {
        Button { pdfImporter = true } label: {
            VStack(spacing: 9) {
                RLIcon("tray", size: 26).foregroundStyle(rl.accent)
                Text("Drop a lease PDF").font(rl.ui(15, .semibold)).foregroundStyle(rl.ink)
                Text("or click to choose").font(rl.ui(12.5)).foregroundStyle(rl.ink3)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
            .background(dropTargeted ? rlMix(rl.accent, rl.surface2, 0.10) : rl.surface2,
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(dropTargeted ? rl.accent : rl.line2)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .onDrop(of: [.pdf], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { leasePDF = url } }
            }
            return true
        }
    }

    private func selectedFileCard(_ url: URL) -> some View {
        HStack(spacing: 12) {
            RLIcon("lease", size: 16).foregroundStyle(rl.accent)
                .frame(width: 34, height: 34)
                .background(rlMix(rl.accent, rl.win, 0.11), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(rl.ui(14, .semibold)).foregroundStyle(rl.ink).lineLimit(1)
                HStack(spacing: 5) {
                    RLIcon("check", size: 11).foregroundStyle(rl.ok)
                    Text("Ready to check").font(rl.ui(12)).foregroundStyle(rl.ok)
                }
            }
            Spacer(minLength: 8)
            Button { pdfImporter = true } label: {
                Text("Change").font(rl.ui(12.5, .medium)).foregroundStyle(rl.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(rl.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(rl.line2, lineWidth: 1))
    }

    // MARK: deal context (always-visible on-ramp — the negotiation thread)

    private var dealContextSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("Deal context")
            TextField("Paste your negotiation email thread — we'll pull out the numbers and check them.",
                      text: $thread, axis: .vertical)
                .textFieldStyle(.plain).font(rl.ui(13)).foregroundStyle(rl.ink).lineLimit(3...10)
                .padding(10)
                .background(threadDropTargeted ? rlMix(rl.accent, rl.surface, 0.10) : rl.surface,
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(threadDropTargeted ? rl.accent : rl.line2, lineWidth: 1))
                .onDrop(of: [.fileURL, .plainText], isTargeted: $threadDropTargeted) { providers in
                    handleThreadDrop(providers)
                }
        }
    }

    private func handleThreadDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                DispatchQueue.main.async { thread = text }
            }
            return true
        }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let s = value as? String else { return }
            DispatchQueue.main.async { thread = s }
        }
        return true
    }

    // MARK: optional attachments

    @ViewBuilder private var dealRow: some View {
        if let deal = dealSheet {
            attachedRow(icon: "tablecells", title: deal.lastPathComponent,
                        subtitle: "Deal sheet") { dealSheet = nil }
        } else {
            addChip(icon: "tablecells", title: "Deal sheet",
                    hint: "match negotiated terms") { dealImporter = true }
        }
    }

    @ViewBuilder private var focusRow: some View {
        if focusOpen || !context.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    fieldLabel("Focus")
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.15)) { context = ""; focusOpen = false } } label: {
                        RLIcon("x", size: 11).foregroundStyle(rl.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear focus note")
                }
                TextField("e.g. check rent matches the negotiated total economics",
                          text: $context, axis: .vertical)
                    .textFieldStyle(.plain).font(rl.ui(13)).foregroundStyle(rl.ink).lineLimit(1...3)
                    .padding(10)
                    .background(rl.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(rl.line2, lineWidth: 1))
            }
        } else {
            addChip(icon: "spark", title: "Add a focus note",
                    hint: "steer the AI's advisory pass") {
                withAnimation(.easeOut(duration: 0.15)) { focusOpen = true }
            }
        }
    }

    // MARK: provider chip — read-only; click to configure in the AI settings popover

    private var providerChip: some View {
        Button { providerOpen.toggle() } label: {
            HStack(spacing: 9) {
                RLIcon("cog", size: 13).foregroundStyle(rl.ink3)
                Text("Using \(ws.provider.shortTitle)").font(rl.ui(12.5, .medium)).foregroundStyle(rl.ink2)
                Text("· \(ws.model.isEmpty ? "default model" : ws.model)")
                    .font(rl.ui(12.5)).foregroundStyle(rl.ink3).lineLimit(1)
                Spacer(minLength: 0)
                RLIcon("chev", size: 12).foregroundStyle(rl.ink4)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(rl.surface2.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $providerOpen, arrowEdge: .bottom) {
            // The popover is a detached environment branch — re-inject the live theme and
            // hand the same workspace store in explicitly.
            VStack(alignment: .leading, spacing: 0) { AISettingsSection(ws: ws) }
                .frame(width: 264).padding(16).background(rl.surface)
                .environment(\.rl, ws.theme)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { ws.showRunSheet = false } label: {
                Text("Cancel").font(rl.ui(13, .medium)).foregroundStyle(rl.ink2)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(rl.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(rl.line2, lineWidth: 1))
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)

            Button {
                guard let leasePDF else { return }
                ws.startRun(leasePDF: leasePDF,
                            deal: DealContext(thread: thread, dealSheet: dealSheet, context: context))
            } label: {
                HStack(spacing: 7) {
                    Text("Run check").font(rl.ui(13, .semibold))
                    RLIcon("chev", size: 12)
                }
                .foregroundStyle(rl.win)
                .padding(.horizontal, 15).padding(.vertical, 8)
                .background(leasePDF == nil ? rl.ink4 : rl.ink, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(leasePDF == nil)
        }
    }

    // MARK: reusable rows

    private func addChip(icon: String, title: String, hint: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RLIcon("plus", size: 11).foregroundStyle(rl.accent)
                RLIcon(icon, size: 13).foregroundStyle(rl.ink3)
                Text(title).font(rl.ui(13, .medium)).foregroundStyle(rl.ink)
                Text("· \(hint)").font(rl.ui(12)).foregroundStyle(rl.ink3).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(rl.surface2.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(rl.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func attachedRow(icon: String, title: String, subtitle: String,
                             onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            RLIcon(icon, size: 13).foregroundStyle(rl.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(rl.ui(13, .semibold)).foregroundStyle(rl.ink).lineLimit(1)
                Text(subtitle).font(rl.ui(11.5)).foregroundStyle(rl.ink3)
            }
            Spacer(minLength: 8)
            Button(action: onClear) { RLIcon("x", size: 12).foregroundStyle(rl.ink3) }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove attachment")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(rl.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(rl.line2, lineWidth: 1))
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t).font(rl.ui(11, .semibold)).tracking(0.4).textCase(.uppercase).foregroundStyle(rl.ink3)
    }
}

extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? .data
}
