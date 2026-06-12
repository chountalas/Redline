import Foundation

enum RunSourceImportError: LocalizedError, Equatable {
    case unsupportedLease(URL)
    case unsupportedDealSheet(URL)
    case missing(URL)
    case copyFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLease(let url):
            "Could not import \(url.lastPathComponent): lease must be a PDF."
        case .unsupportedDealSheet(let url):
            "Could not import \(url.lastPathComponent): deal sheet must be .yaml or .yml."
        case .missing(let url):
            "Could not import \(url.lastPathComponent): file was not found."
        case .copyFailed(let url, let message):
            "Could not import \(url.lastPathComponent): \(message)"
        }
    }
}

struct PreparedRunSource {
    var runtime: RunSource
    var persisted: RunSource
}

enum RunSourceFileStore {
    static func importsDirectory(forStoreURL storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("Imported Sources", isDirectory: true)
    }

    static func importLeasePDF(_ url: URL, storeURL: URL) throws -> URL {
        try importFile(url, kind: .leasePDF, storeURL: storeURL)
    }

    static func importDealSheet(_ url: URL, storeURL: URL) throws -> URL {
        try importFile(url, kind: .dealSheet, storeURL: storeURL)
    }

    static func isImportedSource(_ url: URL, storeURL: URL) -> Bool {
        let dir = importsDirectory(forStoreURL: storeURL).standardizedFileURL
        let source = url.standardizedFileURL
        return source.path.hasPrefix(dir.path + "/")
    }

    static func prepare(
        _ source: RunSource,
        storeURL: URL,
        persistThread: Bool
    ) throws -> PreparedRunSource {
        var runtime = source
        runtime.originalLeaseFilename = originalLeaseFilename(for: source)
        let leaseWasAlreadyImported = isImportedSource(source.leasePDF, storeURL: storeURL)
        runtime.leasePDF = try importFile(source.leasePDF, kind: .leasePDF, storeURL: storeURL)
        do {
            if let dealSheet = source.dealSheet {
                runtime.dealSheet = try importFile(dealSheet, kind: .dealSheet, storeURL: storeURL)
            }
        } catch {
            if !leaseWasAlreadyImported,
               isImportedSource(runtime.leasePDF, storeURL: storeURL) {
                try? FileManager.default.removeItem(at: runtime.leasePDF)
            }
            throw error
        }

        var persisted = runtime
        persisted.apiKey = ""
        if !persistThread { persisted.thread = "" }
        return PreparedRunSource(runtime: runtime, persisted: persisted)
    }

    private enum SourceKind { case leasePDF, dealSheet }

    private static func importFile(_ url: URL, kind: SourceKind, storeURL: URL) throws -> URL {
        switch kind {
        case .leasePDF:
            guard RunSheetFileIntake.isPDF(url) else { throw RunSourceImportError.unsupportedLease(url) }
        case .dealSheet:
            guard RunSheetFileIntake.isDealSheet(url) else { throw RunSourceImportError.unsupportedDealSheet(url) }
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw RunSourceImportError.missing(url) }

        let dir = importsDirectory(forStoreURL: storeURL)
        let standardizedSource = url.standardizedFileURL
        if isImportedSource(standardizedSource, storeURL: storeURL) {
            return url
        }

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = uniqueDestination(for: url, in: dir)
            try fm.copyItem(at: url, to: destination)
            return destination
        } catch {
            throw RunSourceImportError.copyFailed(url, error.localizedDescription)
        }
    }

    private static func uniqueDestination(for url: URL, in directory: URL) -> URL {
        let cleanName = sanitizedFilename(url.lastPathComponent)
        return directory.appendingPathComponent("\(UUID().uuidString)-\(cleanName)")
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let fallback = "source"
        let value = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = value.isEmpty ? fallback : value
        let invalid = CharacterSet(charactersIn: "/:")
        return source.components(separatedBy: invalid).joined(separator: "-")
    }

    private static func originalLeaseFilename(for source: RunSource) -> String {
        let existing = source.originalLeaseFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing, !existing.isEmpty { return existing }
        return source.leasePDF.lastPathComponent
    }
}
