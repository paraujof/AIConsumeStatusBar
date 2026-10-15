public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}
