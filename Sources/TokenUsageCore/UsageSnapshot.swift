public struct UsageSnapshot: Equatable, Sendable {
    public let totals: TokenCounts
    public let topSessions: [SessionSummary]

    public init(totals: TokenCounts, topSessions: [SessionSummary]) {
        self.totals = totals
        self.topSessions = topSessions
    }
}
