import Foundation

/// The persisted shape of the library + per-document review state. Settings persist
/// separately (UserDefaults); the API key is never written to disk.
struct LibrarySnapshot: Codable {
    var documents: [ReviewDoc]
    var groups: [DocGroup]
    var selectedDocID: String
    var reviewed: [String: Bool]
    var notes: [String: String]
}

/// Reads/writes the library snapshot as JSON. The URL is injectable so tests can use a
/// temp file; `defaultURL()` resolves Application Support/Redline/library.json.
enum LibraryStore {
    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Redline", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("library.json")
    }

    static func save(_ snapshot: LibrarySnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    /// Returns nil when no file exists or the file is unreadable/corrupt — a missing or bad
    /// store should never crash the app; it falls back to the first-run empty state.
    static func load(from url: URL) -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }   // absent → first run
        if let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            return snapshot
        }
        // Exists but won't decode (corrupt, or an old/incompatible shape). Move it aside so the
        // next persist() can't silently overwrite it — the data stays recoverable.
        let quarantine = url.deletingLastPathComponent()
            .appendingPathComponent("library.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: quarantine)
        return nil
    }
}
