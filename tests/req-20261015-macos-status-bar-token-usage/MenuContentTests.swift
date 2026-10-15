import Foundation
import Testing

@testable import TokenUsageCore

// Background of every scenario: the current local time is "2026-10-15 10:00".

@Suite("Menu bar item, breakdown, period, aggregation and top sessions")
struct MenuContentTests {

    // ---------- Presence ----------

    // PARTIAL: the process-level part (one item, no Dock icon, no window, app terminates) needs the app
    // shell; only the menu model's Quit action is checked here.
    @Test("Quit removes the menu bar item")
    func quitRemovesTheMenuBarItem() throws {
        let model = try menu([try tokensRec(10, at: "2026-10-15 09:00")])
        #expect(model.lines.contains(.action("Quit", .quit)))
    }

    // ---------- Menu bar item ----------

    @Test("Title shows this month's total tokens")
    func titleShowsThisMonthsTotalTokens() throws {
        let model = try menu([
            try tokensRec(2500, at: "2026-10-03 08:20"),
            try tokensRec(10000, at: "2026-10-15 09:50"),
        ])
        #expect(model.title == "Claude total: 12.5k tokens")
    }

    // PARTIAL: "to the left of the title" is a UI layout fact; the model's icon properties are checked.
    @Test("Menu bar item shows an icon before the title")
    func menuBarItemShowsAnIconBeforeTheTitle() throws {
        let model = try menu([try tokensRec(12500, at: "2026-10-15 09:00")])
        #expect(!model.iconSymbolName.isEmpty)
        #expect(model.iconIsTemplate)
        #expect(model.title == "Claude total: 12.5k tokens")
    }

    // PARTIAL: legibility in Light/Dark is guaranteed by a template (monochrome) image; checked at model level.
    @Test("Icon stays visible in both menu bar appearances", arguments: ["Light", "Dark"])
    func iconStaysVisibleInBothMenuBarAppearances(appearance: String) throws {
        let state = AppState(lastSuccess: nil, currentFailure: nil, isRefreshing: true)
        let model = MenuPresenter.render(state, now: at("2026-10-15 10:00"), calendar: testCalendar)
        #expect(model.iconIsTemplate, "appearance \(appearance)")
        #expect(!model.iconSymbolName.isEmpty)
    }

    @Test(
        "Compact token formatting",
        arguments: [
            (950, "950"), (1000, "1k"), (12500, "12.5k"), (840_000, "840k"), (999_950, "1M"),
            (1_250_000, "1.3M"), (1_240_000_000, "1.2B"),
        ])
    func compactTokenFormatting(tokens: Int, shown: String) throws {
        #expect(CompactNumberFormatter.string(tokens) == shown)
        let model = try menu([try tokensRec(tokens, at: "2026-10-15 09:00")])
        #expect(model.title == "Claude total: \(shown) tokens")
        #expect(model.shows("Total this month: \(shown) tokens"))
    }

    @Test("Title while the first refresh is in progress")
    func titleWhileTheFirstRefreshIsInProgress() {
        let state = AppState(lastSuccess: nil, currentFailure: nil, isRefreshing: true)
        let model = MenuPresenter.render(state, now: at("2026-10-15 10:00"), calendar: testCalendar)
        #expect(model.title == "Claude total: … tokens")
        #expect(model.shows("Total this month: —"))
        #expect(!model.showsLine(withPrefix: "Input:"))
        #expect(model.shows("No data yet"))
    }

    // ---------- Breakdown by token type ----------

    @Test("Menu shows the total divided by token type")
    func menuShowsTheTotalDividedByTokenType() throws {
        let model = try menu([
            try rec("2026-10-15 09:30", input: 100, output: 50, cacheCreation: 30, cacheRead: 20)
        ])
        #expect(model.title == "Claude total: 200 tokens")
        #expect(
            model.contains(inOrder: [
                "Total this month: 200 tokens", "Input: 100", "Output: 50", "Cache write: 30", "Cache read: 20",
            ]))
    }

    @Test("Token types are added up across all records of the month")
    func tokenTypesAreAddedUpAcrossAllRecordsOfTheMonth() throws {
        let model = try menu([
            try rec("2026-10-02 11:00", input: 1000, output: 2000, cacheCreation: 3000, cacheRead: 4000),
            try rec("2026-10-14 16:00", input: 500, output: 500, cacheCreation: 0, cacheRead: 1_500_000),
        ])
        #expect(model.shows("Total this month: 1.5M tokens"))
        #expect(model.shows("Input: 1.5k"))
        #expect(model.shows("Output: 2.5k"))
        #expect(model.shows("Cache write: 3k"))
        #expect(model.shows("Cache read: 1.5M"))
    }

    @Test("Missing token fields count as zero")
    func missingTokenFieldsCountAsZero() throws {
        let model = try menu([
            try rec("2026-10-15 09:30", input: 100, output: 50, cacheCreation: nil, cacheRead: nil)
        ])
        #expect(model.title == "Claude total: 150 tokens")
        #expect(model.shows("Cache write: 0"))
        #expect(model.shows("Cache read: 0"))
    }

    // ---------- Period ----------

    @Test("Usage from earlier days of the current month is counted")
    func usageFromEarlierDaysOfTheCurrentMonthIsCounted() throws {
        let model = try menu([
            try tokensRec(300_000, at: "2026-10-01 00:10"),
            try tokensRec(120_000, at: "2026-10-15 08:20"),
        ])
        #expect(model.title == "Claude total: 420k tokens")
    }

    @Test("Usage from previous months is not counted")
    func usageFromPreviousMonthsIsNotCounted() throws {
        let model = try menu([
            try tokensRec(300_000, at: "2026-09-30 23:50"),
            try tokensRec(120_000, at: "2026-10-01 00:10"),
        ])
        #expect(model.title == "Claude total: 120k tokens")
    }

    @Test("Total starts over at the start of a new month")
    func totalStartsOverAtTheStartOfANewMonth() throws {
        let records = [
            try tokensRec(500_000, at: "2026-10-31 22:00"),
            try tokensRec(700, at: "2026-11-01 00:01"),
        ]
        let october = try menu(records, now: "2026-10-31 23:58")
        #expect(october.title == "Claude total: 500k tokens")
        let november = try menu(records, now: "2026-11-01 00:03")
        #expect(november.title == "Claude total: 700 tokens")
    }

    @Test("A session that spans the month boundary counts only this month's tokens")
    func aSessionThatSpansTheMonthBoundaryCountsOnlyThisMonthsTokens() throws {
        let model = try menu([
            try tokensRec(4000, at: "2026-09-30 23:30", session: "s-1"),
            try tokensRec(1500, at: "2026-10-01 00:20", session: "s-1"),
        ])
        #expect(model.shows("Total this month: 1.5k tokens"))
        #expect(model.shows("1. alpha · 30/09/2026 23:30 · 1.5k"))
    }

    @Test("Records with a future timestamp are ignored")
    func recordsWithAFutureTimestampAreIgnored() throws {
        let model = try menu([
            try tokensRec(200, at: "2026-10-15 09:00"),
            try tokensRec(500, at: "2026-10-15 11:00"),
        ])
        #expect(model.title == "Claude total: 200 tokens")
    }

    // ---------- Aggregation ----------

    @Test("Duplicate usage records are counted once")
    func duplicateUsageRecordsAreCountedOnce() throws {
        let original = try rec(
            "2026-10-15 09:00", session: "s-1", messageId: "msg_01", requestId: "req_01", input: 200, output: 100)
        let copy = try rec(
            "2026-10-15 09:00", session: "s-1", messageId: "msg_01", requestId: "req_01", input: 200, output: 100)
        let twoFiles = UsageScan(
            files: [
                UsageFileDigest(path: "/h/.claude/projects/alpha/one.jsonl", records: [original], nonEmptyLineCount: 1),
                UsageFileDigest(path: "/h/.claude/projects/alpha/two.jsonl", records: [copy], nonEmptyLineCount: 1),
            ], permissionDeniedFileCount: 0, unreadableFileCount: 0)
        let snap = try aggregateScan(twoFiles, now: "2026-10-15 10:00").get()
        let model = MenuPresenter.render(
            successState(snap, completedAt: "2026-10-15 10:00"), now: at("2026-10-15 10:00"), calendar: testCalendar)
        #expect(model.title == "Claude total: 300 tokens")
        #expect(model.shows("Input: 200"))
        #expect(model.shows("Output: 100"))
        #expect(snap.topSessions.map(\.tokens).reduce(0, +) == 300)
    }

    @Test("Records in every project folder are counted")
    func recordsInEveryProjectFolderAreCounted() throws {
        let alpha = UsageFileDigest(
            path: "/h/.claude/projects/alpha/a.jsonl",
            records: [try tokensRec(200, at: "2026-10-15 09:00", session: "s-a", cwd: "/w/alpha")],
            nonEmptyLineCount: 1)
        let beta = UsageFileDigest(
            path: "/h/.claude/projects/beta/b.jsonl",
            records: [try tokensRec(100, at: "2026-10-15 09:10", session: "s-b", cwd: "/w/beta")],
            nonEmptyLineCount: 1)
        let both = UsageScan(files: [alpha, beta], permissionDeniedFileCount: 0, unreadableFileCount: 0)
        let snap = try aggregateScan(both, now: "2026-10-15 10:00").get()
        let model = MenuPresenter.render(
            successState(snap, completedAt: "2026-10-15 10:00"), now: at("2026-10-15 10:00"), calendar: testCalendar)
        #expect(model.title == "Claude total: 300 tokens")
    }

    // GAP: "Only ~/.claude/projects is read" (see report) has a data-layer test seam that is not in
    // the interfaces available to ac-tester. Not written.

    @Test("Records without a session identifier count in the total but are not ranked")
    func recordsWithoutASessionIdentifierCountInTheTotalButAreNotRanked() throws {
        let model = try menu([
            try tokensRec(1, at: "2026-10-15 09:00", session: "s-1"),
            try tokensRec(399, at: "2026-10-15 09:05", session: "s-1"),
            try tokensRec(100, at: "2026-10-15 09:30", session: nil),
        ])
        #expect(model.shows("Total this month: 500 tokens"))
        #expect(model.sessionLines.count == 1)
        #expect(model.shows("1. alpha · 15/10/2026 09:00 · 400"))
    }

    // ---------- Top 5 sessions ----------

    @Test("Menu shows total, breakdown, top sessions, last update and actions")
    func menuShowsTotalBreakdownTopSessionsLastUpdateAndActions() throws {
        let records: [UsageRecord] = [
            // s-a: 4,200,000
            try rec(
                "2026-10-15 09:12", session: "s-a", cwd: "/w/ai-consume-status-bar", cacheRead: 2_000_000),
            try rec(
                "2026-10-15 09:55", session: "s-a", cwd: "/w/ai-consume-status-bar", input: 290_000,
                output: 1_000_000, cacheCreation: 910_000),
            // s-b: 1,250,000
            try rec("2026-10-07 07:40", session: "s-b", cwd: "/w/website", cacheRead: 1_160_000),
            try rec("2026-10-07 08:30", session: "s-b", cwd: "/w/website", cacheCreation: 90_000),
            // s-c: 840,000
            try rec("2026-10-02 08:05", session: "s-c", cwd: "/w/infra", cacheRead: 400_000),
            try rec("2026-10-02 08:10", session: "s-c", cwd: "/w/infra", cacheRead: 440_000),
        ]
        let model = try menu(records)
        #expect(
            model.texts == [
                "Total this month: 6.3M tokens",
                "Input: 290k",
                "Output: 1M",
                "Cache write: 1M",
                "Cache read: 4M",
                "Top sessions this month",
                "1. ai-consume-status-bar · 15/10/2026 09:12 · 4.2M",
                "2. website · 07/10/2026 07:40 · 1.3M",
                "3. infra · 02/10/2026 08:05 · 840k",
                "Updated 10:00",
                "Refresh now",
                "Quit",
            ])
        #expect(model.lines.contains(.action("Refresh now", .refreshNow)))
        #expect(model.lines.contains(.header("Top sessions this month")))
    }

    @Test("Only the 5 sessions with the most tokens are listed")
    func onlyThe5SessionsWithTheMostTokensAreListed() throws {
        var records: [UsageRecord] = []
        let rows: [(String, String, String, Int)] = [
            ("s-1", "p1", "08:01", 100), ("s-2", "p2", "08:02", 700), ("s-3", "p3", "08:03", 300),
            ("s-4", "p4", "08:04", 600), ("s-5", "p5", "08:05", 200), ("s-6", "p6", "08:06", 500),
            ("s-7", "p7", "08:07", 400),
        ]
        for (session, project, first, tokens) in rows {
            records += try sessionRecords(
                session, project: project, first: "2026-10-15 \(first)", last: "2026-10-15 08:30", tokens: tokens)
        }
        let model = try menu(records)
        #expect(model.shows("Total this month: 2.8k tokens"))
        #expect(
            model.sessionLines == [
                "1. p2 · 15/10/2026 08:02 · 700",
                "2. p4 · 15/10/2026 08:04 · 600",
                "3. p6 · 15/10/2026 08:06 · 500",
                "4. p7 · 15/10/2026 08:07 · 400",
                "5. p3 · 15/10/2026 08:03 · 300",
            ])
    }

    @Test("Fewer than 5 sessions this month")
    func fewerThan5SessionsThisMonth() throws {
        let records =
            try sessionRecords(
                "s-1", project: "alpha", first: "2026-10-03 09:00", last: "2026-10-03 09:20", tokens: 900)
            + sessionRecords(
                "s-2", project: "beta", first: "2026-10-15 09:30", last: "2026-10-15 09:40", tokens: 300)
        let model = try menu(records)
        #expect(model.sessionLines.count == 2)
        #expect(
            model.sessionLines == [
                "1. alpha · 03/10/2026 09:00 · 900",
                "2. beta · 15/10/2026 09:30 · 300",
            ])
    }

    @Test("Sessions with equal tokens are ordered by most recent activity")
    func sessionsWithEqualTokensAreOrderedByMostRecentActivity() throws {
        let records =
            try sessionRecords(
                "s-1", project: "alpha", first: "2026-10-15 08:00", last: "2026-10-15 08:40", tokens: 500)
            + sessionRecords(
                "s-2", project: "beta", first: "2026-10-15 08:10", last: "2026-10-15 09:40", tokens: 500)
        let model = try menu(records)
        #expect(
            model.sessionLines == [
                "1. beta · 15/10/2026 08:10 · 500",
                "2. alpha · 15/10/2026 08:00 · 500",
            ])
    }

    @Test("Sessions with equal tokens and equal last activity are ordered by session identifier")
    func sessionsWithEqualTokensAndEqualLastActivityAreOrderedBySessionIdentifier() throws {
        let records =
            try sessionRecords(
                "s-b", project: "beta", first: "2026-10-15 08:10", last: "2026-10-15 09:40", tokens: 500)
            + sessionRecords(
                "s-a", project: "alpha", first: "2026-10-15 08:00", last: "2026-10-15 09:40", tokens: 500)
        let model = try menu(records)
        #expect(
            model.sessionLines == [
                "1. alpha · 15/10/2026 08:00 · 500",
                "2. beta · 15/10/2026 08:10 · 500",
            ])
    }

    @Test("Session with no recorded working directory")
    func sessionWithNoRecordedWorkingDirectory() throws {
        let records = [
            try tokensRec(50, at: "2026-10-15 09:05", session: "s-1", cwd: nil),
            try tokensRec(200, at: "2026-10-15 09:20", session: "s-1", cwd: nil),
        ]
        let model = try menu(records)
        #expect(model.shows("1. Unknown project · 15/10/2026 09:05 · 250"))
    }

    @Test("Selecting a session line does nothing")
    func selectingASessionLineDoesNothing() throws {
        let records = try sessionRecords(
            "s-1", project: "alpha", first: "2026-10-15 09:00", last: "2026-10-15 09:30", tokens: 400)
        let model = try menu(records)
        // Session lines are informational (.info), so no action can be attached to them.
        #expect(model.lines.contains(.info("1. alpha · 15/10/2026 09:00 · 400")))
        let actions = model.lines.compactMap { line -> MenuAction? in
            if case .action(_, let action) = line { return action }
            return nil
        }
        #expect(actions == [.refreshNow, .quit])
    }

    // ---------- Last update time ----------

    @Test("Last successful update on an earlier day shows its date")
    func lastSuccessfulUpdateOnAnEarlierDayShowsItsDate() throws {
        let snap = try snapshot([try tokensRec(420, at: "2026-10-14 23:40")], now: "2026-10-14 23:50")
        var state = successState(snap, completedAt: "2026-10-14 23:50")
        state.currentFailure = .unreadableData
        let model = MenuPresenter.render(state, now: at("2026-10-15 10:00"), calendar: testCalendar)
        #expect(model.shows("Updated 14/10/2026 23:50"))
    }

    // ---------- Empty / first run ----------

    @Test("No Claude Code usage this month")
    func noClaudeCodeUsageThisMonth() throws {
        let model = try menu([try tokensRec(900, at: "2026-09-28 18:10")])
        #expect(model.title == "Claude total: 0 tokens")
        #expect(model.shows("Total this month: 0 tokens"))
        #expect(model.shows("Input: 0"))
        #expect(model.shows("Output: 0"))
        #expect(model.shows("Cache write: 0"))
        #expect(model.shows("Cache read: 0"))
        #expect(model.shows("No sessions this month"))
        #expect(!model.showsLine(withPrefix: "Update failed"))
    }

    @Test("Claude Code data folder exists but holds no files")
    func claudeCodeDataFolderExistsButHoldsNoFiles() throws {
        let empty = UsageScan(files: [], permissionDeniedFileCount: 0, unreadableFileCount: 0)
        let snap = try aggregateScan(empty, now: "2026-10-15 10:00").get()
        let model = MenuPresenter.render(
            successState(snap, completedAt: "2026-10-15 10:00"), now: at("2026-10-15 10:00"), calendar: testCalendar)
        #expect(model.title == "Claude total: 0 tokens")
        #expect(model.shows("No sessions this month"))
        #expect(!model.showsLine(withPrefix: "Update failed"))
    }

    // ---------- Privacy (menu) ----------

    @Test("Conversation content is never shown in the menu")
    func conversationContentIsNeverShownInTheMenu() throws {
        let model = try menu([
            try rec("2026-10-15 09:00", session: "s-1", input: 10, text: "SECRET-PROMPT-TEXT-123")
        ])
        #expect(model.title.contains("SECRET-PROMPT-TEXT-123") == false)
        #expect(model.texts.allSatisfy { !$0.contains("SECRET-PROMPT-TEXT-123") })
        #expect(model.sessionLines.count == 1)
    }
}
