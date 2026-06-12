import AppKit
import Foundation
import UniformTypeIdentifiers

enum RunSheetFileIntake {
    static let leaseDropTypes: [UTType] = [.fileURL, .pdf]

    static func isPDF(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .pdf)
        }
        return url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
    }

    static func isDealSheet(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "yaml" || ext == "yml"
    }

    static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return fileURL(from: value)
        }
        if let value = item as? String {
            return fileURL(from: value)
        }
        return nil
    }

    static func makeOpenPanel(allowedContentTypes: [UTType]) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        return panel
    }

    static func droppedPDFFilename(from url: URL, suggestedName: String?) -> String {
        let rawName = cleanFilename(suggestedName) ?? cleanFilename(url.lastPathComponent) ?? "lease.pdf"
        let rawURL = URL(fileURLWithPath: rawName)
        guard !rawURL.pathExtension.isEmpty else { return "\(rawName).pdf" }
        guard !isPDF(rawURL) else { return rawName }
        return "\(rawURL.deletingPathExtension().lastPathComponent).pdf"
    }

    static func displayFilename(for url: URL, originalFilename: String?) -> String {
        cleanFilename(originalFilename) ?? url.lastPathComponent
    }

    static func copyDroppedPDFToTemporaryURL(_ url: URL, suggestedName: String? = nil) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("redline-dropped-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent(
            droppedPDFFilename(from: url, suggestedName: suggestedName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    static func isTemporaryDroppedPDF(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL
        return parent.deletingLastPathComponent().path == temp.path
            && parent.lastPathComponent.hasPrefix("redline-dropped-")
    }

    static func removeTemporaryDroppedPDF(_ url: URL) {
        guard isTemporaryDroppedPDF(url) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static func cleanFilename(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let basename = URL(fileURLWithPath: trimmed).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !basename.isEmpty else { return nil }
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = basename.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func fileURL(from value: String) -> URL? {
        if let url = URL(string: value), url.isFileURL {
            return url
        }
        return URL(fileURLWithPath: value)
    }
}
