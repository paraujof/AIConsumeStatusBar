import Foundation

@MainActor
public final class RefreshCoordinator {
    private struct Attempt {
        let id: UInt64
        var worker: Task<Void, Never>
        var timeoutTimer: Task<Void, Never>
        var outcomeApplied: Bool
    }

    private let source: any UsageSource
    private let sleeper: any Sleeper
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let timeout: Duration
    private let autoRefreshInterval: Duration
    private let onStateChange: @MainActor (AppState) -> Void
    private let log: @Sendable (RefreshLogEvent) -> Void

    public private(set) var state = AppState()
    private var attempt: Attempt?
    private var nextAttemptId: UInt64 = 0
    private var loopTask: Task<Void, Never>?
    private var outcomeWaiters: [CheckedContinuation<Void, Never>] = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        source: any UsageSource,
        sleeper: any Sleeper,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar,
        timeout: Duration = .seconds(15),
        autoRefreshInterval: Duration = .seconds(300),
        log: @escaping @Sendable (RefreshLogEvent) -> Void = { _ in },
        onStateChange: @escaping @MainActor (AppState) -> Void
    ) {
        self.source = source
        self.sleeper = sleeper
        self.now = now
        self.calendar = calendar
        self.timeout = timeout
        self.autoRefreshInterval = autoRefreshInterval
        self.log = log
        self.onStateChange = onStateChange
    }

    public func refresh() {
        if attempt != nil {
            log(.skippedInProgress)
            return
        }
        nextAttemptId += 1
        let id = nextAttemptId
        state.isRefreshing = true
        onStateChange(state)

        let source = self.source
        let now = self.now
        let calendar = self.calendar
        let worker = Task.detached(priority: .utility) { [weak self] in
            let result: Result<UsageSnapshot, RefreshFailure>
            do {
                let moment = now()
                let period = ReportingPeriod.currentMonth(now: moment, calendar: calendar)
                let scan = try await source.scan()
                result = UsageAggregator.aggregate(scan, period: period)
            } catch let failure as RefreshFailure {
                result = .failure(failure)
            } catch is CancellationError {
                result = .failure(.timedOut)
            } catch {
                result = .failure(.unreadableData)
            }
            await self?.workerExited(id: id, result: result)
        }
        let sleeper = self.sleeper
        let timeout = self.timeout
        let timer = Task { @MainActor [weak self] in
            do {
                try await sleeper.sleep(for: timeout)
            } catch {
                return
            }
            self?.timeoutFired(id: id)
        }
        attempt = Attempt(id: id, worker: worker, timeoutTimer: timer, outcomeApplied: false)
    }

    public func startAutomaticRefresh() {
        refresh()
        loopTask?.cancel()
        let sleeper = self.sleeper
        let interval = self.autoRefreshInterval
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleeper.sleep(for: interval)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        if let attempt {
            attempt.timeoutTimer.cancel()
            attempt.worker.cancel()
        }
        attempt = nil
        state.isRefreshing = false
        resumeOutcomeWaiters()
        resumeIdleWaiters()
    }

    public func waitForOutcome() async {
        guard let attempt, !attempt.outcomeApplied else { return }
        await withCheckedContinuation { outcomeWaiters.append($0) }
    }

    public func waitForIdle() async {
        guard attempt != nil else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func timeoutFired(id: UInt64) {
        guard var current = attempt, current.id == id, !current.outcomeApplied else { return }
        state.currentFailure = .timedOut
        current.outcomeApplied = true
        attempt = current
        onStateChange(state)
        resumeOutcomeWaiters()
        log(.failed(reason: "timed out"))
        current.worker.cancel()
    }

    private func workerExited(id: UInt64, result: Result<UsageSnapshot, RefreshFailure>) {
        guard let current = attempt, current.id == id else { return }
        if !current.outcomeApplied {
            current.timeoutTimer.cancel()
            switch result {
            case .success(let snapshot):
                state.lastSuccess = SuccessfulRefresh(snapshot: snapshot, completedAt: now())
                state.currentFailure = nil
            case .failure(let failure):
                state.currentFailure = failure
                log(.failed(reason: failure.reason))
            }
            attempt?.outcomeApplied = true
            resumeOutcomeWaiters()
        } else {
            log(.lateResultDiscarded)
        }
        attempt = nil
        state.isRefreshing = false
        onStateChange(state)
        resumeIdleWaiters()
    }

    private func resumeOutcomeWaiters() {
        let waiters = outcomeWaiters
        outcomeWaiters = []
        for w in waiters { w.resume() }
    }

    private func resumeIdleWaiters() {
        let waiters = idleWaiters
        idleWaiters = []
        for w in waiters { w.resume() }
    }
}
