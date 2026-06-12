import PDFKit
import SwiftUI

/// A sheet that shows a source PDF opened to a cited page (G6).
struct SourcePageView: View {
    let request: SourcePageRequest
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            switch SourcePDFState.state(for: request.url) {
            case .available(let url):
                PDFSourceView(url: url, pageIndex: request.page)
            case .missing:
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.questionmark")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Source PDF not found")
                        .font(.headline)
                    Text("The original PDF was moved or deleted. Replace the source PDF from the document menu, then re-check.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 640, idealHeight: 840)
    }
}

struct PDFSourceView: NSViewRepresentable {
    let url: URL
    var pageIndex: Int? = nil   // 1-based cited page

    final class Coordinator {
        var loadedPath: String?
        var loadedPageIndex: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        update(view, context: context)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        update(nsView, context: context)
    }

    private func update(_ view: PDFView, context: Context) {
        let path = url.standardizedFileURL.path
        if context.coordinator.loadedPath != path {
            view.document = PDFDocument(url: url)
            context.coordinator.loadedPath = path
            context.coordinator.loadedPageIndex = nil
        }

        guard let pageIndex,
              context.coordinator.loadedPageIndex != pageIndex,
              let target = view.document?.page(at: max(0, pageIndex - 1)) else { return }
        context.coordinator.loadedPageIndex = pageIndex
        DispatchQueue.main.async { view.go(to: target) }
    }
}
