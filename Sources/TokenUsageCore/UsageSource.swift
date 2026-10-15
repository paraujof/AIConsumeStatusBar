public protocol UsageSource: Sendable {
    /// Throws RefreshFailure.noData / .permissionDenied for root-level failures,
    /// CancellationError when cancelled. Never modifies the data.
    func scan() async throws -> UsageScan
}
