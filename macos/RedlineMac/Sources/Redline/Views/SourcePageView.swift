import PDFKit
import SwiftUI

/// A sheet that shows a source lease PDF opened to a cited page (G6).
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
            PDFKitPage(url: request.url, pageIndex: request.page)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 640, idealHeight: 840)
    }
}

private struct PDFKitPage: NSViewRepresentable {
    let url: URL
    let pageIndex: Int   // 1-based cited page

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        if let document = PDFDocument(url: url) {
            view.document = document
            let target = document.page(at: max(0, pageIndex - 1))
            if let target {
                // defer so the view has its document laid out before scrolling
                DispatchQueue.main.async { view.go(to: target) }
            }
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}
