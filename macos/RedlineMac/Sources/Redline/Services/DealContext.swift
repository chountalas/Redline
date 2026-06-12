import Foundation

/// The deal-context inputs gathered in the run sheet, bundled for `startRun`.
struct DealContext: Codable, Equatable {
    var thread: String = ""
    var dealSheet: URL? = nil
    var context: String = ""
    var saveThread: Bool = false
}
