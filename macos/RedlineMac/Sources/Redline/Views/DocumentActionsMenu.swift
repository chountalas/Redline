import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentActionsMenu: View {
    @Environment(Workspace.self) private var ws
    let doc: ReviewDoc

    var body: some View {
        Button("Rename...") { promptRename() }
            .disabled(ws.isRunning)
        if doc.source != nil {
            Button("Replace source PDF...") { replaceSourcePDF() }
                .disabled(ws.isRunning)
        }
        Divider()
        Button("Delete", role: .destructive) { confirmDelete() }
            .disabled(ws.isRunning)
    }

    private func promptRename() {
        let alert = NSAlert()
        alert.messageText = "Rename document"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = doc.name
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ws.renameDoc(doc.id, to: field.stringValue)
    }

    private func replaceSourcePDF() {
        let panel = RunSheetFileIntake.makeOpenPanel(allowedContentTypes: [.pdf])
        panel.message = "Choose the replacement source PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ws.replaceSourcePDF(for: doc.id, with: url)
        } catch {
            ws.run = .failed(RunFailure.map(error))
        }
    }

    private func confirmDelete() {
        guard DocumentDeleteConfirmation.askToDelete(doc: doc) else { return }
        ws.deleteDoc(doc.id)
    }
}

enum DocumentDeleteConfirmation {
    typealias Prompt = (_ message: String, _ informativeText: String) -> Bool

    static func shouldDelete(doc: ReviewDoc, prompt: Prompt) -> Bool {
        prompt(
            "Delete \(doc.name)?",
            "This removes the review from your library and deletes its imported source PDF if no other document uses it."
        )
    }

    @MainActor
    static func askToDelete(doc: ReviewDoc) -> Bool {
        shouldDelete(doc: doc) { message, informativeText in
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = informativeText
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }
}
