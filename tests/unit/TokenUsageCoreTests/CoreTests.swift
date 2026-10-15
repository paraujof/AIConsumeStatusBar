import Foundation
import Testing

@testable import TokenUsageCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

private func rec(
    _ at: String, session: String? = "s", cwd: String? = "/x/alpha", key: String? = nil, input: Int = 0, output: Int = 0
) -> UsageRecord {
    UsageRecord(
        timestamp: date(at), sessionId: session, cwd: cwd, responseKey: key,
        tokens: TokenCounts(input: input, output: output))
}

private func file(_ path: String, _ records: [UsageRecord], lines: Int? = nil) -> UsageFileDigest {
    UsageFileDigest(path: path, records: records, nonEmptyLineCount: lines ?? records.count)
}

@Suite struct FormatterTests {
    @Test(arguments: [
        (950, "950"), (1000, "1k"), (12500, "12.5k"), (840_000, "840k"), (999_950, "1M"),
        (1_250_000, "1.3M"), (1_240_000_000, "1.2B"), (0, "0"), (999, "999"),
    ])
    func compact(_ value: Int, _ expected: String) {
        #expect(CompactNumberFormatter.string(value) == expected)
    }

    @Test func updatedFormat() {
        let f = DisplayDateFormatter(calendar: utc)
        let now = date("2026-10-15 10:00")
        #expect(f.updated(date("2026-10-15 09:05"), now: now) == "09:05")
        #expect(f.updated(date("2026-10-14 23:50"), now: now) == "14/10/2026 23:50")
    }
}

@Suite struct ParserTests {
    @Test func parsesValidLine() throws {
        let line = """
            {"timestamp":"2026-10-15T09:30:00.123Z","sessionId":"s-1","cwd":"/a/b","requestId":"r","message":{"id":"m","usage":{"input_tokens":100,"output_tokens":50}}}
            """
        let r = try #require(UsageRecordParser.parse(line: Data(line.utf8)))
        #expect(r.tokens == TokenCounts(input: 100, output: 50, cacheCreation: 0, cacheRead: 0))
        #expect(r.responseKey == "m:r")
        #expect(r.sessionId == "s-1")
    }

    @Test func rejectsInvalid() {
        for line in [
            "not json \"usage\"", "{}",
            "{\"message\":{\"usage\":{\"input_tokens\":-1}},\"timestamp\":\"2026-10-15T09:30:00Z\"}",
            "{\"message\":{\"usage\":{\"input_tokens\":1.5}},\"timestamp\":\"2026-10-15T09:30:00Z\"}",
            "{\"message\":{\"usage\":{}},\"timestamp\":\"yesterday\"}",
        ] {
            #expect(UsageRecordParser.parse(line: Data(line.utf8)) == nil)
        }
    }

    @Test func emptySessionIsAbsent() throws {
        let line = "{\"timestamp\":\"2026-10-15T09:30:00Z\",\"sessionId\":\"\",\"message\":{\"usage\":{}}}"
        let r = try #require(UsageRecordParser.parse(line: Data(line.utf8)))
        #expect(r.sessionId == nil)
        #expect(r.tokens == .zero)
    }
}

@Suite struct AggregatorTests {
    let period = ReportingPeriod.currentMonth(now: date("2026-10-15 10:00"), calendar: utc)

    @Test func periodBoundaries() {
        #expect(period.start == date("2026-10-01 00:00"))
        #expect(period.contains(date("2026-10-15 10:00")))
        #expect(!period.contains(date("2026-10-15 10:01")))
        #expect(!period.contains(date("2026-09-30 23:59")))
    }

    @Test func dedupAcrossFilesAttributesToEarliestFile() throws {
        let a = file("/b", [rec("2026-10-15 09:00", session: "s-1", key: "m:r", input: 200, output: 100)])
        let b = file("/a", [rec("2026-10-15 09:00", session: "s-2", key: "m:r", input: 200, output: 100)])
        let early = file("/c", [rec("2026-10-15 08:00", session: "s-2", key: "x:y", input: 1)])
        let snap = try UsageAggregator.aggregate(UsageScan(files: [a, b, early]), period: period).get()
        #expect(snap.totals.total == 301)
        // Earliest file wins attribution: the duplicate counts once, toward s-2.
        #expect(snap.topSessions.map(\.sessionId) == ["s-2"])
        #expect(snap.topSessions.reduce(0) { $0 + $1.tokens } == 301)
    }

    @Test func spanningSessionAndOrdering() throws {
        let f = file(
            "/f",
            [
                rec("2026-09-30 23:30", session: "s-1", input: 4000),
                rec("2026-10-01 00:20", session: "s-1", input: 1500),
                rec("2026-10-15 08:00", session: "s-b", cwd: nil, input: 500),
                rec("2026-10-15 08:00", session: "s-a", input: 500),
                rec("2026-10-15 11:00", session: "s-f", input: 999),
            ])
        let snap = try UsageAggregator.aggregate(UsageScan(files: [f]), period: period).get()
        #expect(snap.totals.total == 2500)
        #expect(snap.topSessions.map(\.sessionId) == ["s-1", "s-a", "s-b"])
        #expect(snap.topSessions[0].start == date("2026-09-30 23:30"))
        #expect(snap.topSessions[0].tokens == 1500)
        #expect(snap.topSessions[0].projectName == "alpha")
        #expect(snap.topSessions[2].projectName == nil)
    }

    @Test func topFiveOnly() throws {
        let recs = (1...7).map { rec("2026-10-15 08:0\($0)", session: "s-\($0)", input: $0 * 100) }
        let snap = try UsageAggregator.aggregate(UsageScan(files: [file("/f", recs)]), period: period).get()
        #expect(snap.topSessions.count == 5)
        #expect(snap.topSessions.first?.sessionId == "s-7")
    }

    @Test func classification() {
        #expect(
            UsageAggregator.aggregate(UsageScan(files: [file("/f", [], lines: 2)]), period: period)
                == .failure(.unreadableData))
        #expect(
            UsageAggregator.aggregate(UsageScan(files: [], permissionDeniedFileCount: 1), period: period)
                == .failure(.permissionDenied))
        #expect(
            UsageAggregator.aggregate(UsageScan(files: []), period: period)
                == .success(UsageSnapshot(totals: .zero, topSessions: [])))
        let old = file("/f", [rec("2026-09-28 18:10", input: 5)])
        #expect(
            UsageAggregator.aggregate(UsageScan(files: [old]), period: period)
                == .success(UsageSnapshot(totals: .zero, topSessions: [])))
    }
}

@Suite struct PresenterTests {
    @Test func beforeAnyRefresh() {
        let m = MenuPresenter.render(AppState(), now: date("2026-10-15 10:00"), calendar: utc)
        #expect(m.title == "Claude total: \u{2026} tokens")
        #expect(
            m.lines.compactMap(\.text) == [
                "Total this month: \u{2014}", "Top sessions this month", "No data yet", "Refresh now", "Quit",
            ])
        #expect(m.iconIsTemplate)
    }

    @Test func successAndStaleFailure() {
        let session = SessionSummary(
            sessionId: "s", projectName: nil, start: date("2026-10-15 09:05"), lastActivity: date("2026-10-15 09:06"),
            tokens: 250)
        let snap = UsageSnapshot(
            totals: TokenCounts(input: 100, output: 50, cacheCreation: 30, cacheRead: 20), topSessions: [session])
        let state = AppState(
            lastSuccess: SuccessfulRefresh(snapshot: snap, completedAt: date("2026-10-14 23:50")),
            currentFailure: .unreadableData)
        let m = MenuPresenter.render(state, now: date("2026-10-15 10:00"), calendar: utc)
        #expect(m.title == "Claude total: 200 tokens")
        #expect(
            m.lines.compactMap(\.text) == [
                "Total this month: 200 tokens", "Input: 100", "Output: 50", "Cache write: 30", "Cache read: 20",
                "Top sessions this month", "1. Unknown project \u{00B7} 15/10/2026 09:05 \u{00B7} 250",
                "Updated 14/10/2026 23:50", "Update failed: unreadable data", "Refresh now", "Quit",
            ])
    }
}

// MARK: - Coordinator

actor ControlledSleeper: Sleeper {
    private var waiters: [(Duration, CheckedContinuation<Void, any Error>)] = []

    func sleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { waiters.append((duration, $0)) }
    }

    func release(_ duration: Duration) {
        let matching = waiters.filter { $0.0 == duration }
        waiters.removeAll { $0.0 == duration }
        for (_, c) in matching { c.resume() }
    }

    func hasWaiter(_ duration: Duration) -> Bool { waiters.contains { $0.0 == duration } }
}

extension ControlledSleeper {
    func waitUntilSleeping(_ duration: Duration) async {
        while !(await hasWaiter(duration)) { await Task.yield() }
    }
}

final class FakeSource: UsageSource, @unchecked Sendable {
    enum Mode {
        case result(UsageScan)
        case hang
        case fail(RefreshFailure)
    }
    private let lock = NSLock()
    private var _mode: Mode
    private var _calls = 0
    private var _concurrent = 0
    private var _maxConcurrent = 0
    private var hangContinuations: [CheckedContinuation<Void, Never>] = []

    init(_ mode: Mode) { _mode = mode }
    var calls: Int { lock.withLock { _calls } }
    var maxConcurrent: Int { lock.withLock { _maxConcurrent } }
    func setMode(_ m: Mode) { lock.withLock { _mode = m } }
    func unhang() {
        let c = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let x = hangContinuations
            hangContinuations = []
            return x
        }
        for continuation in c { continuation.resume() }
    }

    func scan() async throws -> UsageScan {
        let mode = lock.withLock { () -> Mode in
            _calls += 1
            _concurrent += 1
            _maxConcurrent = max(_maxConcurrent, _concurrent)
            return _mode
        }
        defer { lock.withLock { _concurrent -= 1 } }
        switch mode {
        case .result(let s): return s
        case .fail(let f): throw f
        case .hang:
            // Deliberately ignores cancellation.
            await withCheckedContinuation { c in lock.withLock { hangContinuations.append(c) } }
            return UsageScan(files: [file("/late", [rec("2026-10-15 09:00", input: 999)])])
        }
    }
}

@MainActor
@Suite struct CoordinatorTests {
    let okScan = UsageScan(files: [file("/f", [rec("2026-10-15 09:00", input: 420)])])

    fileprivate func make(_ source: FakeSource, _ sleeper: ControlledSleeper) -> RefreshCoordinator {
        RefreshCoordinator(
            source: source, sleeper: sleeper, now: { date("2026-10-15 10:00") }, calendar: utc,
            onStateChange: { _ in })
    }

    @Test func successThenFailureKeepsStaleValues() async {
        let source = FakeSource(.result(okScan))
        let c = make(source, ControlledSleeper())
        c.refresh()
        await c.waitForIdle()
        #expect(c.state.lastSuccess?.snapshot.totals.total == 420)
        source.setMode(.fail(.permissionDenied))
        c.refresh()
        await c.waitForIdle()
        #expect(c.state.currentFailure == .permissionDenied)
        #expect(c.state.lastSuccess?.snapshot.totals.total == 420)
        source.setMode(.result(okScan))
        c.refresh()
        await c.waitForIdle()
        #expect(c.state.currentFailure == nil)
    }

    @Test func timeoutWithNonCancellableSourceAndSingleFlight() async {
        let source = FakeSource(.hang)
        let sleeper = ControlledSleeper()
        let c = make(source, sleeper)
        c.refresh()
        #expect(c.state.isRefreshing)
        c.refresh()
        await sleeper.waitUntilSleeping(.seconds(15))
        await sleeper.release(.seconds(15))
        await c.waitForOutcome()
        #expect(c.state.currentFailure == .timedOut)
        #expect(c.state.isRefreshing)
        c.refresh()  // dropped in the zombie window
        #expect(source.calls == 1)
        #expect(source.maxConcurrent == 1)
        source.unhang()
        await c.waitForIdle()
        #expect(!c.state.isRefreshing)
        #expect(c.state.currentFailure == .timedOut)
        #expect(c.state.lastSuccess == nil)  // late result discarded
        source.setMode(.result(okScan))
        c.refresh()
        await c.waitForIdle()
        #expect(c.state.currentFailure == nil)
        #expect(c.state.lastSuccess?.snapshot.totals.total == 420)
    }

    @Test func automaticRefreshEveryInterval() async {
        let source = FakeSource(.result(okScan))
        let sleeper = ControlledSleeper()
        let c = make(source, sleeper)
        c.startAutomaticRefresh()
        await c.waitForIdle()
        #expect(source.calls == 1)
        await sleeper.waitUntilSleeping(.seconds(300))
        await sleeper.release(.seconds(300))
        while source.calls < 2 { await Task.yield() }
        await c.waitForIdle()
        #expect(source.calls == 2)
        c.stop()
    }
}
