public enum RefreshFailure: Error, Equatable, Sendable {
    case noData, permissionDenied, unreadableData, timedOut

    public var reason: String {
        switch self {
        case .noData: return "no Claude Code data found"
        case .permissionDenied: return "permission denied"
        case .unreadableData: return "unreadable data"
        case .timedOut: return "timed out"
        }
    }
}
