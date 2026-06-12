import Foundation

enum SourcePDFState: Equatable {
    case available(URL)
    case missing(URL)

    static func state(for url: URL) -> SourcePDFState {
        FileManager.default.fileExists(atPath: url.path) ? .available(url) : .missing(url)
    }
}
