import Foundation
import Testing

@testable import TokenUsageCore

// MARK: - Time

let testTimeZone = TimeZone(identifier: "Europe/Madrid")!

var testCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = testTimeZone
    return calendar
}

/// Parses "yyyy-MM-dd HH:mm" as local time in `testTimeZone`.
func at(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = testTimeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

func isoUTC(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")!
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ text: String) { value = at(text) }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    func set(_ text: String) { now = at(text) }
}

// MARK: - Records

struct SetupError: Error { let message: String }

private let idLock = NSLock()
nonisolated(unsafe) private var idCounter = 0
private func nextId() -> Int {
    idLock.withLock {
        idCounter += 1
        return idCounter
    }
}

/// JSON line in the Claude Code format (spec A3). Pass nil for a token field to omit it.
func jsonLine(
    _ time: String,
    session: String? = "s-1",
    cwd: String? = "/Users/test/work/alpha",
    messageId: String? = nil,
    requestId: String? = nil,
    input: Int? = 0,
    output: Int? = 0,
    cacheCreation: Int? = 0,
    cacheRead: Int? = 0,
    text: String? = nil
) -> Data {
    var usage: [String: Any] = [:]
    if let input { usage["input_tokens"] = input }
    if let output { usage["output_tokens"] = output }
    if let cacheCreation { usage["cache_creation_input_tokens"] = cacheCreation }
    if let cacheRead { usage["cache_read_input_tokens"] = cacheRead }
    let n = nextId()
    var message: [String: Any] = ["id": messageId ?? "msg_auto_\(n)", "usage": usage]
    if let text { message["content"] = [["type": "text", "text": text]] }
    var object: [String: Any] = [
        "type": "assistant",
        "timestamp": isoUTC(at(time)),
        "requestId": requestId ?? "req_auto_\(n)",
        "message": message,
    ]
    if let session { object["sessionId"] = session }
    if let cwd { object["cwd"] = cwd }
    return try! JSONSerialization.data(withJSONObject: object)
}

func rec(
    _ time: String,
    session: String? = "s-1",
    cwd: String? = "/Users/test/work/alpha",
    messageId: String? = nil,
    requestId: String? = nil,
    input: Int? = 0,
    output: Int? = 0,
    cacheCreation: Int? = 0,
    cacheRead: Int? = 0,
    text: String? = nil
) throws -> UsageRecord {
    let line = jsonLine(
        time, session: session, cwd: cwd, messageId: messageId, requestId: requestId, input: input,
        output: output, cacheCreation: cacheCreation, cacheRead: cacheRead, text: text)
    return try #require(UsageRecordParser.parse(line: line), "test setup: line must parse as a usage record")
}

/// A record whose counted tokens are exactly `tokens` (all input).
func tokensRec(
    _ tokens: Int, at time: String, session: String? = "s-1", cwd: String? = "/Users/test/work/alpha"
) throws -> UsageRecord {
    try rec(time, session: session, cwd: cwd, input: tokens)
}

/// Two records (first, last) of a session whose counted tokens add up to `tokens`.
func sessionRecords(
    _ session: String, project: String?, first: String, last: String, tokens: Int
) throws -> [UsageRecord] {
    let cwd = project.map { "/Users/test/work/\($0)" }
    return [
        try tokensRec(1, at: first, session: session, cwd: cwd),
        try tokensRec(tokens - 1, at: last, session: session, cwd: cwd),
    ]
}

func makeScan(_ records: [UsageRecord], extraNonRecordLines: Int = 0) -> UsageScan {
    UsageScan(
        files: [
            UsageFileDigest(
                path: "/Users/test/.claude/projects/alpha/a.jsonl", records: records,
                nonEmptyLineCount: records.count + extraNonRecordLines)
        ],
        permissionDeniedFileCount: 0, unreadableFileCount: 0)
}

func aggregateScan(_ scan: UsageScan, now: String) -> Result<UsageSnapshot, RefreshFailure> {
    UsageAggregator.aggregate(scan, period: .currentMonth(now: at(now), calendar: testCalendar))
}

func snapshot(_ records: [UsageRecord], now: String = "2026-10-15 10:00") throws -> UsageSnapshot {
    try aggregateScan(makeScan(records), now: now).get()
}

func successState(_ snapshot: UsageSnapshot, completedAt: String) -> AppState {
    AppState(
        lastSuccess: SuccessfulRefresh(snapshot: snapshot, completedAt: at(completedAt)),
        currentFailure: nil, isRefreshing: false)
}

/// Aggregate + render, as the app does after a successful refresh at `now`.
func menu(_ records: [UsageRecord], now: String = "2026-10-15 10:00") throws -> MenuModel {
    let snap = try snapshot(records, now: now)
    return MenuPresenter.render(successState(snap, completedAt: now), now: at(now), calendar: testCalendar)
}

extension MenuModel {
    var texts: [String] { lines.compactMap(\.text) }
    var sessionLines: [String] {
        texts.filter { $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }
    }
    func shows(_ text: String) -> Bool { texts.contains(text) }
    func showsLine(withPrefix prefix: String) -> Bool { texts.contains { $0.hasPrefix(prefix) } }
    /// True when `expected` appears as consecutive menu lines, in order.
    func contains(inOrder expected: [String]) -> Bool {
        let all = texts
        guard all.count >= expected.count, !expected.isEmpty else { return false }
        for start in 0...(all.count - expected.count) where Array(all[start..<start + expected.count]) == expected {
            return true
        }
        return false
    }
}

// MARK: - Coordinator fakes

final class FakeSource: UsageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: @Sendable () async throws -> UsageScan
    private var calls = 0
    init(_ handler: @escaping @Sendable () async throws -> UsageScan) { self.handler = handler }
    convenience init(records: [UsageRecord]) { self.init { makeScan(records) } }
    var callCount: Int { lock.withLock { calls } }
    func setHandler(_ new: @escaping @Sendable () async throws -> UsageScan) { lock.withLock { handler = new } }
    func scan() async throws -> UsageScan {
        let current = lock.withLock { () -> @Sendable () async throws -> UsageScan in
            calls += 1
            return handler
        }
        return try await current()
    }
}

actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

final class ManualSleeper: Sleeper, @unchecked Sendable {
    private struct Waiter {
        let id: Int
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private let lock = NSLock()
    private var waiters: [Waiter] = []
    private var nextWaiterId = 0

    func sleep(for duration: Duration) async throws {
        let id = lock.withLock { () -> Int in
            nextWaiterId += 1
            return nextWaiterId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.withLock { waiters.append(Waiter(id: id, duration: duration, continuation: c)) }
            }
        } onCancel: {
            let removed = lock.withLock { () -> Waiter? in
                guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return waiters.remove(at: index)
            }
            removed?.continuation.resume(throwing: CancellationError())
        }
    }

    func hasWaiter(_ duration: Duration) -> Bool { lock.withLock { waiters.contains { $0.duration == duration } } }

    /// Resumes every sleeper that asked for `duration`.
    func fire(_ duration: Duration) {
        let fired = lock.withLock { () -> [Waiter] in
            let matching = waiters.filter { $0.duration == duration }
            waiters.removeAll { $0.duration == duration }
            return matching
        }
        for waiter in fired { waiter.continuation.resume() }
    }
}

func waitUntil(_ what: String = "condition", _ condition: @escaping @Sendable () -> Bool) async throws {
    for _ in 0..<2000 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw SetupError(message: "timed out waiting for \(what)")
}

@MainActor
func makeCoordinator(
    source: FakeSource, sleeper: ManualSleeper = ManualSleeper(), clock: Clock
) -> RefreshCoordinator {
    RefreshCoordinator(
        source: source, sleeper: sleeper, now: { clock.now }, calendar: testCalendar, onStateChange: { _ in })
}

@MainActor
func renderedMenu(_ coordinator: RefreshCoordinator, clock: Clock) -> MenuModel {
    MenuPresenter.render(coordinator.state, now: clock.now, calendar: testCalendar)
}
