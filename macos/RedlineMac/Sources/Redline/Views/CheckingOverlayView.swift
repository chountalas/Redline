import SwiftUI

/// The re-check pipeline animation that replaces the report pane while a check runs.
/// Plain-language steps; only the first (reading) uses AI — the rest are exact rules.
struct CheckingOverlayView: View {
    @Environment(\.rl) private var rl
    let doc: ReviewDoc?
    let step: Int
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RLIcon("spark", size: 18).foregroundStyle(rl.ai)
                    .frame(width: 34, height: 34)
                    .background(rl.aiSoft, in: RoundedRectangle(cornerRadius: 10))
                Text(doc.map { "Re-checking \($0.name)" } ?? "Checking your document")
                    .font(rl.serif(23, .medium)).foregroundStyle(rl.ink)
            }
            Text(doc.map { "\($0.kind) · \($0.pages) pages" } ?? "Reading the document and running the checks")
                .font(rl.ui(13)).foregroundStyle(rl.ink3)
                .padding(.leading, 46).padding(.top, 8).padding(.bottom, 26)

            VStack(spacing: 9) {
                ForEach(Array(CHECK_STEPS.enumerated()), id: \.element.id) { i, s in
                    stepRow(s, done: step > i, active: step == i)
                }
            }

            HStack(spacing: 8) {
                RLIcon("spark", size: 13)
                Text("Only the reading step uses AI — the checks are exact").font(rl.ui(12))
            }
            .foregroundStyle(rl.ink3)
            .padding(.top, 24)

            if let onCancel {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(rl.ui(13, .semibold))
                    .foregroundStyle(rl.ink3)
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 40).padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(rl.win)
    }

    private func stepRow(_ s: CheckStep, done: Bool, active: Bool) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(done ? rl.ok : rl.surface2)
                if done {
                    RLIcon("check", size: 14).foregroundStyle(.white)
                } else if active {
                    ProgressView().controlSize(.small)
                } else {
                    RLIcon("chev", size: 13).foregroundStyle(rl.ink3)
                }
            }
            .frame(width: 25, height: 25)

            Text(s.lab).font(rl.ui(14, .semibold)).foregroundStyle(rl.ink)
            Spacer(minLength: 10)
            Text(s.nt).font(rl.ui(12)).foregroundStyle(rl.ink3)
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(rl.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? rl.accent : rl.line, lineWidth: 1)
        )
        .opacity(active || done ? 1 : 0.45)
    }
}
