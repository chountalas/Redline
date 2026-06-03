import Foundation

/// G1a seam: a pluggable source of pre-filled deal context. The shipped/open-source build
/// uses `ManualDealSource` (the user types/pastes it). Future local integrations can
/// conform later to prefill context — without changing the run sheet.
protocol DealSource {
    func prefill() async -> DealContext?
}

struct ManualDealSource: DealSource {
    func prefill() async -> DealContext? { nil }
}
