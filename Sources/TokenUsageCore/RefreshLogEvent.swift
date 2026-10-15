/// Events the refresh coordinator reports to an injected logger. Carries no user data.
public enum RefreshLogEvent: Sendable, Equatable {
    case skippedInProgress
    case lateResultDiscarded
    case failed(reason: String)
}
