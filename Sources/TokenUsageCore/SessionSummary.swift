import Foundation

public struct SessionSummary: Equatable, Sendable {
    public let sessionId: String
    public let projectName: String?
    public let start: Date
    public let lastActivity: Date
    public let tokens: Int

    public init(sessionId: String, projectName: String?, start: Date, lastActivity: Date, tokens: Int) {
        self.sessionId = sessionId
        self.projectName = projectName
        self.start = start
        self.lastActivity = lastActivity
        self.tokens = tokens
    }
}
