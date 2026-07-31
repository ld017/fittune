import Foundation

/// Coalesces repeated HealthKit observer notifications while a refresh is in flight.
/// A burst produces one immediate refresh and at most one follow-up refresh.
struct HealthRefreshGate: Equatable {
    private(set) var isRefreshing = false
    private(set) var hasPendingRefresh = false

    mutating func requestRefresh() -> Bool {
        guard !isRefreshing else {
            hasPendingRefresh = true
            return false
        }
        isRefreshing = true
        return true
    }

    /// Finishes the current refresh and atomically starts a coalesced follow-up.
    @discardableResult
    mutating func finishRefreshAndBeginPending() -> Bool {
        guard hasPendingRefresh else {
            isRefreshing = false
            return false
        }
        hasPendingRefresh = false
        isRefreshing = true
        return true
    }
}
