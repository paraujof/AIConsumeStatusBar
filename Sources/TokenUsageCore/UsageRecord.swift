import Foundation

public struct UsageRecord: Equatable, Sendable {
    public let timestamp: Date
    public let sessionId: String?
    public let cwd: String?
    public let responseKey: String?
    public let tokens: TokenCounts

    public init(timestamp: Date, sessionId: String?, cwd: String?, responseKey: String?, tokens: TokenCounts) {
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.cwd = cwd
        self.responseKey = responseKey
        self.tokens = tokens
    }
}
