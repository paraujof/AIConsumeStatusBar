import Foundation
import Testing

@testable import TokenUsageCore

@Suite("Refresh and error handling")
@MainActor
struct RefreshAndErrorTests {

    private func total(_ coordinator: RefreshCoordinator) -> Int? {
        coordinator.state.lastSuccess?.snapshot.totals.total
    }

    // ---------- Empty / first run (failures) ----------

    @Test("No Claude Code data on this Mac")
    func noClaudeCodeDataOnThisMac() async throws {
        let clock = Clock("2026-10-15 10:00")
        let source = FakeSource { throw RefreshFailure.noData }
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        await coordinator.waitForOutcome()
        let model = renderedMenu(coordinator, clock: clock)
        #expect(model.title == "Claude total: — tokens")
        #expect(model.shows("Total this month: —"))
        #expect(!model.showsLine(withPrefix: "Input:"))
        #expect(model.shows("No data yet"))
        #expect(model.shows("Update failed: no Claude Code data found"))
        coordinator.stop()
    }

    // ---------- Refresh ----------

    @Test("Automatic refresh every 5 minutes")
    func automaticRefreshEvery5Minutes() async throws {
        let clock = Clock("2026-10-15 10:00")
        let sleeper = ManualSleeper()
        let source = FakeSource(records: [try tokensRec(420, at: "2026-10-15 09:00")])
        let coordinator = makeCoordinator(source: source, sleeper: sleeper, clock: clock)
        coordinator.startAutomaticRefresh()
        try await waitUntil("first refresh") { source.callCount == 1 }
        await coordinator.waitForOutcome()
        #expect(total(coordinator) == 420)

        source.setHandler {
            makeScan([
                try! tokensRec(420, at: "2026-10-15 09:00", session: "s-1"),
                try! tokensRec(130, at: "2026-10-15 10:03", session: "s-1"),
            ])
        }
        clock.set("2026-10-15 10:05")
        try await waitUntil("5 minute timer armed") { sleeper.hasWaiter(.seconds(300)) }
        sleeper.fire(.seconds(300))
        try await waitUntil("second refresh") { source.callCount == 2 }
        await coordinator.waitForOutcome()

        let model = renderedMenu(coordinator, clock: clock)
        #expect(model.title == "Claude total: 550 tokens")
        #expect(model.shows("Updated 10:05"))
        coordinator.stop()
    }

    // The "Refresh now" action is MenuAction.refreshNow, which the app forwards to refresh().
    @Test("Manual refresh")
    func manualRefresh() async throws {
        let clock = Clock("2026-10-15 10:00")
        let source = FakeSource(records: [try tokensRec(420, at: "2026-10-15 09:00")])
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        await coordinator.waitForOutcome()
        await coordinator.waitForIdle()
        #expect(renderedMenu(coordinator, clock: clock).title == "Claude total: 420 tokens")

        source.setHandler {
            makeScan([
                try! tokensRec(420, at: "2026-10-15 09:00", session: "s-1"),
                try! tokensRec(180, at: "2026-10-15 09:30", session: "s-1"),
            ])
        }
        coordinator.refresh()
        await coordinator.waitForOutcome()
        #expect(renderedMenu(coordinator, clock: clock).title == "Claude total: 600 tokens")
        #expect(renderedMenu(coordinator, clock: clock).lines.contains(.action("Refresh now", .refreshNow)))
        coordinator.stop()
    }

    // PARTIAL: the wake-from-sleep notification hook belongs to the app shell; a wake triggers refresh().
    @Test("Refresh on wake from sleep")
    func refreshOnWakeFromSleep() async throws {
        let clock = Clock("2026-10-15 10:00")
        let source = FakeSource(records: [try tokensRec(420, at: "2026-10-15 09:00")])
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        await coordinator.waitForOutcome()
        await coordinator.waitForIdle()
        source.setHandler {
            makeScan([
                try! tokensRec(420, at: "2026-10-15 09:00", session: "s-1"),
                try! tokensRec(280, at: "2026-10-15 09:30", session: "s-1"),
            ])
        }
        coordinator.refresh()  // what the wake notification invokes
        await coordinator.waitForOutcome()
        #expect(renderedMenu(coordinator, clock: clock).title == "Claude total: 700 tokens")
        coordinator.stop()
    }

    @Test("Manual refresh while a refresh is in progress")
    func manualRefreshWhileARefreshIsInProgress() async throws {
        let clock = Clock("2026-10-15 10:00")
        let gate = Gate()
        let source = FakeSource {
            await gate.wait()
            return makeScan([try! tokensRec(10, at: "2026-10-15 09:00")])
        }
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        try await waitUntil("worker started") { source.callCount == 1 }
        coordinator.refresh()  // user selects "Refresh now"
        for _ in 0..<50 { await Task.yield() }
        #expect(source.callCount == 1)
        await gate.open()
        await coordinator.waitForIdle()
        #expect(source.callCount == 1)
        coordinator.stop()
    }

    @Test("Menu opens while a refresh is in progress")
    func menuOpensWhileARefreshIsInProgress() async throws {
        let clock = Clock("2026-10-15 10:00")
        let gate = Gate()
        let source = FakeSource {
            await gate.wait()
            return makeScan([try! tokensRec(10, at: "2026-10-15 09:00")])
        }
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        try await waitUntil("worker started") { source.callCount == 1 }
        #expect(coordinator.state.isRefreshing)
        let model = renderedMenu(coordinator, clock: clock)  // returns synchronously with the current state
        #expect(model.title == "Claude total: … tokens")
        #expect(model.shows("No data yet"))
        await gate.open()
        await coordinator.waitForIdle()
        coordinator.stop()
    }

    // ---------- Errors ----------

    @Test("Malformed records are skipped and the rest still count")
    func malformedRecordsAreSkippedAndTheRestStillCount() throws {
        #expect(UsageRecordParser.parse(line: Data("{ this is not json \"usage\"".utf8)) == nil)
        #expect(UsageRecordParser.parse(line: Data(#"{"type":"user","message":{"content":"hi"}}"#.utf8)) == nil)
        let records = [try tokensRec(100, at: "2026-10-15 09:00"), try tokensRec(200, at: "2026-10-15 09:10")]
        let result = aggregateScan(makeScan(records, extraNonRecordLines: 2), now: "2026-10-15 10:00")
        let snap = try result.get()
        let model = MenuPresenter.render(
            successState(snap, completedAt: "2026-10-15 10:00"), now: at("2026-10-15 10:00"), calendar: testCalendar)
        #expect(model.title == "Claude total: 300 tokens")
        #expect(!model.showsLine(withPrefix: "Update failed"))
    }

    @Test("No readable usage record at all")
    func noReadableUsageRecordAtAll() async throws {
        let clock = Clock("2026-10-15 10:00")
        let onlyGarbage = UsageScan(
            files: [UsageFileDigest(path: "/h/.claude/projects/alpha/a.jsonl", records: [], nonEmptyLineCount: 3)],
            permissionDeniedFileCount: 0, unreadableFileCount: 0)
        #expect(aggregateScan(onlyGarbage, now: "2026-10-15 10:00") == .failure(.unreadableData))
        let source = FakeSource { onlyGarbage }
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        await coordinator.waitForOutcome()  // the app keeps running: no crash, state is reported
        let model = renderedMenu(coordinator, clock: clock)
        #expect(model.title == "Claude total: — tokens")
        #expect(model.shows("Update failed: unreadable data"))
        coordinator.stop()
    }

    @Test("Reading local data times out")
    func readingLocalDataTimesOut() async throws {
        let clock = Clock("2026-10-15 10:00")
        let sleeper = ManualSleeper()
        let gate = Gate()
        let source = FakeSource {
            await gate.wait()
            return makeScan([try! tokensRec(10, at: "2026-10-15 09:00")])
        }
        let coordinator = makeCoordinator(source: source, sleeper: sleeper, clock: clock)
        coordinator.refresh()
        try await waitUntil("timeout armed") { sleeper.hasWaiter(.seconds(15)) }
        sleeper.fire(.seconds(15))
        await coordinator.waitForOutcome()
        #expect(coordinator.state.currentFailure == .timedOut)
        #expect(renderedMenu(coordinator, clock: clock).shows("Update failed: timed out"))
        await gate.open()
        await coordinator.waitForIdle()
        coordinator.stop()
    }

    @Test("Failure with a previous reading keeps the stale values")
    func failureWithAPreviousReadingKeepsTheStaleValues() async throws {
        let clock = Clock("2026-10-15 10:00")
        let source = FakeSource(records: [try rec("2026-10-15 09:00", input: 300, output: 120)])
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        await coordinator.waitForOutcome()
        await coordinator.waitForIdle()

        source.setHandler { throw RefreshFailure.unreadableData }
        clock.set("2026-10-15 10:05")
        coordinator.refresh()
        await coordinator.waitForOutcome()

        let model = renderedMenu(coordinator, clock: clock)
        #expect(model.title == "Claude total: 420 tokens")
        #expect(model.shows("Total this month: 420 tokens"))
        #expect(model.shows("Input: 300"))
        #expect(model.shows("Output: 120"))
        #expect(model.shows("Updated 10:00"))
        #expect(model.shows("Update failed: unreadable data"))
        coordinator.stop()
    }

    @Test("Successful refresh after a failure clears the error")
    func successfulRefreshAfterAFailureClearsTheError() async throws {
        let clock = Clock("2026-10-15 10:00")
        let sleeper = ManualSleeper()
        let gate = Gate()
        let source = FakeSource {
            await gate.wait()
            return makeScan([])
        }
        let coordinator = makeCoordinator(source: source, sleeper: sleeper, clock: clock)
        coordinator.refresh()
        try await waitUntil("timeout armed") { sleeper.hasWaiter(.seconds(15)) }
        sleeper.fire(.seconds(15))
        await coordinator.waitForOutcome()
        #expect(coordinator.state.currentFailure == .timedOut)
        await gate.open()
        await coordinator.waitForIdle()

        source.setHandler { makeScan([try! tokensRec(500, at: "2026-10-15 09:00")]) }
        coordinator.refresh()
        await coordinator.waitForOutcome()
        let model = renderedMenu(coordinator, clock: clock)
        #expect(model.title == "Claude total: 500 tokens")
        #expect(!model.showsLine(withPrefix: "Update failed"))
        coordinator.stop()
    }

    // ---------- Permissions ----------

    @Test("Permission denied reading Claude Code data")
    func permissionDeniedReadingClaudeCodeData() async throws {
        let clock = Clock("2026-10-15 10:00")
        let source = FakeSource { throw RefreshFailure.permissionDenied }
        let coordinator = makeCoordinator(source: source, clock: clock)
        coordinator.refresh()
        await coordinator.waitForOutcome()  // the app keeps running
        let model = renderedMenu(coordinator, clock: clock)
        #expect(model.title == "Claude total: — tokens")
        #expect(model.shows("Update failed: permission denied"))
        coordinator.stop()
    }
}
