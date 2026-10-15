import Foundation

public struct SuccessfulRefresh: Equatable, Sendable {
    public let snapshot: UsageSnapshot
    public let completedAt: Date

    public init(snapshot: UsageSnapshot, completedAt: Date) {
        self.snapshot = snapshot
        self.completedAt = completedAt
    }
}

public struct AppState: Equatable, Sendable {
    public var lastSuccess: SuccessfulRefresh?
    public var currentFailure: RefreshFailure?
    public var isRefreshing: Bool

    public init(
        lastSuccess: SuccessfulRefresh? = nil, currentFailure: RefreshFailure? = nil, isRefreshing: Bool = false
    ) {
        self.lastSuccess = lastSuccess
        self.currentFailure = currentFailure
        self.isRefreshing = isRefreshing
    }
}
