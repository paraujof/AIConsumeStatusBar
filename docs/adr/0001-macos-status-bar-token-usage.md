# ADR req-20261015-macos-status-bar-token-usage: Native Swift menu bar app that aggregates local Claude Code token usage
Status: accepted (2026-10-15, TL_GATE; implemented in PR #1)
Type: feature
Inputs: work-item.md, spec.md, acceptance.feature

## Context

**Problem.** The scope owner wants this month's Claude Code token total, the total split by
token type, and the top 5 sessions by tokens, visible from the macOS menu bar (spec.md
"Problem", sections 1-8). The only data source is `~/.claude/projects/<folder>/*.jsonl`
(spec section 2, A2). Nothing in the app talks to the network or stores credentials (spec
section 8). The spec leaves technology, minimum macOS version and icon artwork to this ADR
(spec "Out of scope", last bullet).

**Repo state.** The repo has no code, no build files and no ADRs (spec "Current behavior").
`repo-conventions` lists the stack and every command as TODO(team). The toolchain on the
machine is Swift 6.4 with Command Line Tools only (no Xcode) plus python3. So this ADR also
picks the stack, the package layout and the commands. It does not supersede any accepted
ADR, because there are none (`docs/adr/` does not exist).

**Forces and constraints.**
- *No Xcode.* The build has to work with SwiftPM (`swift build` / `swift test`) alone. That
  rules out `.xcodeproj`, asset catalogs, storyboards and Xcode-only test bundles.
- *Architecture guidelines.* I/O sits behind an interface at the edge. Calculations are pure
  functions. Dependencies are injected through initializers. There are no singletons, no
  blocking I/O on the main thread, explicit error types at boundaries, and no new
  third-party dependency without an ADR entry.
- *Testability of the AC.* Almost every scenario fixes "now" (Background: `2026-10-15 10:00`)
  and checks exact strings. So "now", the time zone/calendar, the data root, the timeout
  clock and the refresh scheduler all have to be injectable. Title and menu text have to be
  produced by pure code that can run without AppKit.
- *Data volume.* `~/.claude/projects` can hold hundreds of MB of JSONL, with single lines of
  several MB (tool outputs), and it is re-read every 5 minutes. A refresh must finish within
  15 s (spec section 5) or it counts as `timed out`.
- *Timeout vs. single flight (spec section 5).* "A refresh that has not finished after 15
  seconds counts as failed with `timed out`" and "Only one refresh runs at a time" must both
  hold even when the reading work does not react to cancellation (a blocking `read()` on a
  hung volume, or a test source that never returns). So the timeout outcome cannot depend on
  the reading work having exited.
- *Undocumented format (A3).* The record schema can change, so parsing has to be lenient
  and per line: a bad line is skipped and never fails the refresh (spec section 2).
- *Duplicates (A6, A6b).* Claude Code writes several lines for one response with the same
  `message.id` + `requestId`, and resumed sessions copy records into new files. Dedup must
  be global across files and deterministic.
- *Privacy (spec section 8).* Conversation text must never reach logs, preferences or
  support files.
- *Case-insensitive file system.* On a default APFS volume, `Tests/` and `tests/` are the
  same folder. The workflow already uses `tests/<id>/`, so every test lives under lowercase
  `tests/`.

## Decision

### 1. Stack (established by this ADR)
- **Language:** Swift 6 language mode (strict concurrency), built with the installed Swift
  6.4 toolchain. `swift-tools-version: 6.0`.
- **UI toolkit:** AppKit `NSStatusItem` + `NSMenu`, no SwiftUI.
- **Minimum macOS:** 13.0 (Ventura). This is the lowest version with the SF Symbol
  `gauge.with.dots.needle.33percent` used as the icon, and with `OSAllocatedUnfairLock`
  (used in Decision 9).
- **Package manager:** Swift Package Manager (`Package.swift`, `Package.resolved` only if a
  dependency is ever added).
- **Third-party dependencies:** none. Only Apple frameworks: Foundation, AppKit, `os`
  (Logger, `OSAllocatedUnfairLock`) and Swift Testing (`import Testing`, which ships with the
  Swift 6 toolchain and works under Command Line Tools).
- **Test framework:** Swift Testing, chosen over XCTest because XCTest availability under
  Command Line Tools alone is not guaranteed.

### 2. Package layout and module boundaries (dependency direction points inward)

```
AIConsumeStatusBar (executable, AppKit UI + composition root)
      │ depends on
      ├──────────────► TokenUsageData (filesystem adapter)  ──► TokenUsageCore
      └──────────────────────────────────────────────────────► TokenUsageCore
TokenUsageCore: domain + application logic, Foundation only, no AppKit, no file I/O
```

| Target | Kind | Owns | May import |
|---|---|---|---|
| `TokenUsageCore` | library | Models, line parser, period, aggregation, formatting, app state, menu presentation, `RefreshCoordinator`, `UsageSource` / `Sleeper` protocols | Foundation |
| `TokenUsageData` | library | `LocalClaudeProjectsSource` (the only code that touches the file system) and its per-file cache | Foundation, `os`, `TokenUsageCore` |
| `AIConsumeStatusBar` | executable | `main.swift`, `AppDelegate`, `StatusBarController`, `WakeObserver`, `TaskSleeper`; wires dependencies | AppKit, `os`, `TokenUsageCore`, `TokenUsageData` |
| `TokenUsageCoreTests` | test, `tests/unit/TokenUsageCoreTests/` | implementer's unit tests | `TokenUsageCore` |
| `TokenUsageDataTests` | test, `tests/unit/TokenUsageDataTests/` | implementer's unit tests (temp dirs) | `TokenUsageData`, `TokenUsageCore` |
| `Acceptance_req_20261015_macos_status_bar_token_usage` | test, path `tests/req-20261015-macos-status-bar-token-usage/` | ac-tester's acceptance tests | `TokenUsageCore`, `TokenUsageData` |

General rule for acceptance test targets: the target for `tests/<id>/` is named
`Acceptance_<id with "-" replaced by "_">` and depends on every library target. The
implementer declares it in `Package.swift`, because ac-tester may only write inside
`tests/<id>/`. (SwiftPM rejects a declared target whose folder is missing or has no
sources; the stage order that guarantees `tests/<id>/` has sources before the first
`swift build` is a process decision for TL_GATE, see Consequences > Risks.)

There are no cycles. Business logic never lives in `StatusBarController`: it only renders a
`MenuModel` and forwards two actions (`Refresh now`, `Quit`).

### 3. Core interfaces (`TokenUsageCore`, all `public`, all `Sendable`)

```swift
public struct TokenCounts: Equatable, Sendable {
    public var input: Int, output: Int, cacheCreation: Int, cacheRead: Int
    public var total: Int { input + output + cacheCreation + cacheRead }   // A4
    public static let zero: TokenCounts
}

public struct UsageRecord: Equatable, Sendable {
    public let timestamp: Date
    public let sessionId: String?      // nil when absent or empty (A7)
    public let cwd: String?            // nil when absent or empty
    public let responseKey: String?    // "\(message.id):\(requestId)"; nil if either is missing (then never deduplicated)
    public let tokens: TokenCounts
}

public enum UsageRecordParser {
    /// Returns nil for anything that is not a valid usage record (spec section 2).
    public static func parse(line: Data) -> UsageRecord?
}

public struct UsageFileDigest: Equatable, Sendable {
    public let path: String
    public let records: [UsageRecord]     // valid usage records, in file line order
    public let nonEmptyLineCount: Int
}

public struct UsageScan: Equatable, Sendable {
    public let files: [UsageFileDigest]
    public let permissionDeniedFileCount: Int   // files skipped because open/read was denied
    public let unreadableFileCount: Int         // files skipped for any other I/O error
}

public enum RefreshFailure: Error, Equatable, Sendable {
    case noData, permissionDenied, unreadableData, timedOut
    public var reason: String  // "no Claude Code data found" | "permission denied" | "unreadable data" | "timed out"
}

public protocol UsageSource: Sendable {
    /// Throws RefreshFailure.noData / .permissionDenied for root-level failures,
    /// CancellationError when cancelled. Never modifies the data.
    /// Implementations should honour cancellation, but RefreshCoordinator does not rely on it
    /// (Decision 8).
    func scan() async throws -> UsageScan
}

public struct ReportingPeriod: Equatable, Sendable {
    public let start: Date   // 00:00 local, day 1 of the month containing `now`
    public let end: Date     // `now`
    public static func currentMonth(now: Date, calendar: Calendar) -> ReportingPeriod
    public func contains(_ date: Date) -> Bool   // start <= date && date <= end
}

public struct SessionSummary: Equatable, Sendable {
    public let sessionId: String
    public let projectName: String?   // last path component of cwd; nil → "Unknown project"
    public let start: Date            // earliest attributed record, any period
    public let lastActivity: Date     // latest attributed record inside the period
    public let tokens: Int            // counted tokens inside the period
}

public struct UsageSnapshot: Equatable, Sendable {
    public let totals: TokenCounts            // per-type totals; totals.total is the Total
    public let topSessions: [SessionSummary]  // 0...5, already ordered
}

public enum UsageAggregator {
    public static func aggregate(_ scan: UsageScan, period: ReportingPeriod) -> Result<UsageSnapshot, RefreshFailure>
}

public enum CompactNumberFormatter {
    public static func string(_ value: Int) -> String
}

public struct DisplayDateFormatter: Sendable {
    public init(calendar: Calendar)                  // uses calendar.timeZone
    public func dateTime(_ date: Date) -> String     // "dd/MM/yyyy HH:mm"
    public func updated(_ at: Date, now: Date) -> String  // "HH:mm" if same local day, else "dd/MM/yyyy HH:mm"
}

public struct SuccessfulRefresh: Equatable, Sendable { public let snapshot: UsageSnapshot; public let completedAt: Date }

public struct AppState: Equatable, Sendable {
    public var lastSuccess: SuccessfulRefresh?
    public var currentFailure: RefreshFailure?   // set by a failed or timed-out refresh, cleared by a successful one
    public var isRefreshing: Bool                // true while a reading worker is running (including after its timeout fired)
}

public enum MenuAction: Equatable, Sendable { case refreshNow, quit }
public enum MenuLine: Equatable, Sendable {
    case info(String)                  // informational, no action (totals, breakdown, sessions, Updated, Update failed)
    case header(String)                // "Top sessions this month"
    case separator
    case action(String, MenuAction)    // "Refresh now", "Quit"
    public var text: String?           // nil for .separator
}
public struct MenuModel: Equatable, Sendable {
    public let title: String
    public let iconSymbolName: String  // "gauge.with.dots.needle.33percent"
    public let iconIsTemplate: Bool    // always true
    public let lines: [MenuLine]
}

public enum MenuPresenter {
    public static func render(_ state: AppState, now: Date, calendar: Calendar) -> MenuModel
}

public protocol Sleeper: Sendable { func sleep(for duration: Duration) async throws }

@MainActor
public final class RefreshCoordinator {
    public init(source: any UsageSource,
                sleeper: any Sleeper,
                now: @escaping @Sendable () -> Date,
                calendar: Calendar,
                timeout: Duration = .seconds(15),
                autoRefreshInterval: Duration = .seconds(300),
                onStateChange: @escaping @MainActor (AppState) -> Void)
    public private(set) var state: AppState
    public func refresh()                 // no-op if a reading worker is still running
    public func startAutomaticRefresh()   // refresh() now, then every autoRefreshInterval
    public func stop()                    // cancels the timer loop, the timeout timer and the worker
    public func waitForOutcome() async    // test seam: returns once the current attempt's outcome
                                          // (success, failure or timed out) has been applied,
                                          // even if the worker has not exited; immediate if none
    public func waitForIdle() async       // test seam: returns when no reading worker is running
}
```

### 4. Parsing rules (`UsageRecordParser`, pure)
- Cheap pre-filter: a line that does not contain the bytes `"usage"` is not a usage record
  and is never JSON-decoded.
- Decode with `JSONDecoder` into a private `Decodable` struct that declares only
  `timestamp`, `sessionId`, `cwd`, `requestId`, `message.id` and `message.usage.{input_tokens,
  output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`. Message content,
  prompts and tool output are never decoded into any type (spec section 8).
- Valid usage record = JSON object with a `message.usage` object and a `timestamp` that
  parses as ISO-8601 (with or without fractional seconds). Missing token fields count as 0
  (spec section 2). A negative or non-integer token value makes the line invalid.
- `sessionId` / `cwd` that are empty strings are treated as absent.

### 5. Aggregation rules (`UsageAggregator`, pure, O(N) plus a sort of sessions)
1. Order files by (timestamp of their first valid record, then path), with files that have
   no valid record last. Walk records in that order, and within a file in line order. The
   first time a `responseKey` is seen it is kept and later copies are dropped. This puts
   A6 and A6b into effect: the kept copy is the one in the file with the earliest first
   record, so it counts once in totals, once in per-type totals, and toward exactly one
   session.
2. For each kept record with a `sessionId`, update that session's accumulator: earliest
   timestamp (any period) → `start`, and the `cwd` of the earliest record that has a `cwd`
   → `projectName`.
3. For each kept record with `period.contains(timestamp)`: add its tokens to the totals. If
   it has a `sessionId`, also add them to that session's period tokens and update
   `lastActivity`. Records outside the period, including future ones, add nothing (spec
   section 2, A1).
4. Top sessions: sessions with period tokens > 0, sorted by tokens descending, then
   `lastActivity` descending, then `sessionId` ascending (byte-wise). Take the first 5
   (spec 4.4).
5. Result classification:
   - at least one valid record in the scan → `.success(snapshot)`, even when every record
     falls outside the period (total 0);
   - otherwise, `permissionDeniedFileCount > 0` → `.failure(.permissionDenied)`;
   - otherwise, any non-empty line or `unreadableFileCount > 0` → `.failure(.unreadableData)`;
   - otherwise (no files or only empty files) → `.success` with zero totals and no
     sessions (spec section 7, last paragraph).

### 6. Formatting (pure, locale-independent)
- `CompactNumberFormatter` uses integer arithmetic only (no floating point), so "round
  half up" is exact. For `n < 1_000` it returns `"\(n)"`. Otherwise it picks the unit (k =
  10^3, M = 10^6, B = 10^9) and computes `tenths = (n + unit/20) / (unit/10)`. If `tenths
  >= 10_000` and the unit is not B, it moves to the next unit. It renders `tenths / 10`,
  plus `"." + tenths % 10` when that digit is non-zero, plus the suffix. This produces
  every value in the "Compact token formatting" table (999 950 → `1M`, 1 250 000 → `1.3M`,
  1 240 000 000 → `1.2B`).
- `DisplayDateFormatter` uses `DateFormatter` with locale `en_US_POSIX`, the injected
  calendar's time zone, and the fixed patterns `dd/MM/yyyy HH:mm` and `HH:mm` (A12, A13).
- Literal characters: `…` is U+2026, `—` is U+2014 and the session separator is
  `" · "` (U+00B7 with one space on each side).

### 7. Presentation (`MenuPresenter.render`, pure)
- Title: `Claude total: <compact(lastSuccess.totals.total)> tokens` if `lastSuccess`
  exists. Otherwise `Claude total: — tokens` if `currentFailure != nil`, and otherwise
  `Claude total: … tokens` (spec section 3, A15).
- Lines, in order (spec section 4):
  1. `.info("Total this month: <n> tokens")`, or `.info("Total this month: —")` with no
     success.
  2. Only with a success: `.info("Input: <n>")`, `.info("Output: <n>")`,
     `.info("Cache write: <n>")`, `.info("Cache read: <n>")`.
  3. `.separator`, then `.header("Top sessions this month")`.
  4. Only with a success: up to 5 `.info("<rank>. <project> · <dd/mm/yyyy HH:mm> · <n>")`,
     or `.info("No sessions this month")`. Before any success, no line appears under the
     header, because the session state is unknown.
  5. `.separator`, then `.info("Updated <time>")` or `.info("No data yet")`.
  6. `.info("Update failed: <reason>")` only while `currentFailure != nil`.
  7. `.separator`, `.action("Refresh now", .refreshNow)`, `.action("Quit", .quit)`.
- `isRefreshing` is not rendered (the spec defines no "refreshing" indicator).
- Separators carry no text, so text-order assertions compare `lines.compactMap(\.text)`.
- On failure the snapshot is never replaced, so title, total, breakdown, sessions and
  `Updated` keep the last successful values (stale values, spec sections 3 and 4).

### 8. Refresh orchestration (`RefreshCoordinator`, `@MainActor`, no I/O itself)

The coordinator separates two things that the previous revision tied together: **the
outcome of an attempt** (what the user sees, decided at the latest when the 15 s timer
fires) and **the lifetime of the reading worker** (what single flight protects, which ends
only when the worker really exits). No task group is used, so nothing waits for a child
that ignores cancellation.

**Private state (main-actor isolated):**
```swift
private struct Attempt {
    let id: UInt64                 // monotonically increasing attempt number
    var worker: Task<Void, Never>  // reading + aggregation
    var timeoutTimer: Task<Void, Never>
    var outcomeApplied: Bool       // true once success/failure/timedOut has been shown
}
private var attempt: Attempt?      // non-nil exactly while a reading worker is running
private var nextAttemptId: UInt64 = 0
private var outcomeWaiters: [CheckedContinuation<Void, Never>]   // for waitForOutcome()
private var idleWaiters: [CheckedContinuation<Void, Never>]      // for waitForIdle()
```

**`refresh()` (single flight, spec section 5):**
1. If `attempt != nil`, return immediately: the trigger is dropped and logged as
   "skipped: refresh in progress" (count only). This holds both while the attempt is still
   undecided and after its timeout fired while the worker has not exited yet.
2. Otherwise: `nextAttemptId += 1`, `state.isRefreshing = true`, call `onStateChange`, and
   start two unstructured tasks for attempt `id`:
   - **Worker** — `Task.detached(priority: .utility)`: capture `now()` once, compute
     `ReportingPeriod.currentMonth(now:calendar:)` (month boundary evaluated at every
     refresh), `await source.scan()`, then `UsageAggregator.aggregate` (off the main
     actor). Its result is a `Result<UsageSnapshot, RefreshFailure>`: a `RefreshFailure`
     from the source is kept as is; `CancellationError` maps to `.timedOut` (the only
     cancellation reason other than `stop()`); any other error maps to `.unreadableData`.
     It then calls `await self.workerExited(id: id, result: result)` on the main actor.
   - **Timeout timer** — `Task { @MainActor in }`: `try? await sleeper.sleep(for: timeout)`;
     if the sleep was not cancelled, call `self.timeoutFired(id: id)`.

**`timeoutFired(id:)` (main actor) — applies `timed out` at 15 s, independent of the worker:**
- If `attempt?.id != id` or `attempt.outcomeApplied` → no-op (the worker already won, or
  the attempt is gone).
- Otherwise: `state.currentFailure = .timedOut`, `lastSuccess` unchanged (stale values
  stay), `attempt.outcomeApplied = true`, call `onStateChange`, resume `outcomeWaiters`,
  log "refresh failed: timed out", and call `attempt.worker.cancel()` to ask the worker to
  stop.
- `attempt` is **not** cleared and `state.isRefreshing` **stays true**: the worker may still
  be running, and single flight forbids starting a second scan next to it.

**`workerExited(id:result:)` (main actor) — ends the attempt:**
- If `attempt?.id != id` → no-op (only possible after `stop()`).
- If `attempt.outcomeApplied == false` (the worker finished before 15 s): cancel
  `attempt.timeoutTimer`, then apply the result —
  - success: `lastSuccess = SuccessfulRefresh(snapshot, completedAt: now())`,
    `currentFailure = nil`;
  - failure: `currentFailure = failure`, `lastSuccess` unchanged; logged with its reason.
  Then resume `outcomeWaiters`.
- If `attempt.outcomeApplied == true` (the timeout already fired): **the late result is
  discarded**, whether it is a success or a failure. `currentFailure` stays `.timedOut` and
  `lastSuccess` is not touched. It is logged as "late result discarded" (count only).
  Rationale: the attempt was already reported as failed; replacing that with a result read
  against a "now" captured more than 15 s earlier would be confusing and racy. Files whose
  digests the source completed are still cached in the source (Decision 9), so the next
  refresh is fast.
- In both cases: `attempt = nil`, `state.isRefreshing = false`, call `onStateChange`,
  resume `idleWaiters`. From this point the next trigger starts a new attempt.

**Ordering guarantees.** `timeoutFired` and `workerExited` both run on the main actor and
are serialized. `outcomeApplied` decides which one sets the outcome, so exactly one outcome
is applied per attempt. The attempt `id` check makes stray callbacks from an earlier
attempt harmless.

**Behavior while a timed-out worker has not exited (the "zombie window"):**
| Aspect | Behavior |
|---|---|
| Title / menu | `Update failed: timed out`, title and values from `lastSuccess` (or `—` if none). Shown from second 15, not from worker exit. |
| `state.isRefreshing` | `true` |
| `attempt` (single flight) | still set |
| Triggers (timer tick, `Refresh now`, wake) | dropped, as for any running refresh (spec section 5: no second, parallel refresh) |
| Late result | discarded when the worker exits |
| After the worker exits | `isRefreshing = false`; the next trigger (at the latest the next 5-minute tick) starts a fresh attempt |
| Worker never exits | the app keeps showing `timed out` with stale values and does not start a second scan; logged once per dropped trigger. Decision 9 isolates such a hang on a dedicated I/O thread, so the cooperative pool and the main thread stay free. |

**Triggers** (spec section 5, A11):
- `startAutomaticRefresh()` is called at launch. It runs `refresh()` and then a loop task
  `while !Task.isCancelled { try await sleeper.sleep(for: autoRefreshInterval); refresh() }`.
- `Refresh now` calls `refresh()`.
- Wake: `WakeObserver` subscribes to `NSWorkspace.shared.notificationCenter`
  `didWakeNotification` and calls `refresh()`.
- Triggers that arrive while an attempt exists are dropped (see above).

**`stop()`:** cancels the loop task, `attempt.timeoutTimer` and `attempt.worker`, sets
`attempt = nil`, `isRefreshing = false` and resumes all waiters. A worker that exits later
is ignored by the `id` check.

**Sleeper.** In production `TaskSleeper` (`try await Task.sleep(for:)` on the continuous
clock). Tests inject a controllable sleeper; it receives both the timeout duration (15 s)
and the auto-refresh interval (300 s) and can release each independently by duration.

### 9. File-system adapter (`TokenUsageData.LocalClaudeProjectsSource`)
```swift
public final class LocalClaudeProjectsSource: UsageSource, @unchecked Sendable {
    public init(root: URL, fileManager: FileManager = .default)
    // production root: FileManager.default.homeDirectoryForCurrentUser
    //                    .appendingPathComponent(".claude/projects", isDirectory: true)
    public func scan() async throws -> UsageScan
}
```
- **Dedicated I/O thread.** All file-system work runs on a private serial
  `DispatchQueue(label: "dev.pablo.AIConsumeStatusBar.file-io", qos: .utility)`, not on the
  Swift cooperative pool and never on the main thread. `scan()` is
  `withTaskCancellationHandler { withCheckedThrowingContinuation { queue.async { … } } }
  onCancel: { token.cancel() }`, where `token` is a per-scan `ScanCancellation` backed by
  `OSAllocatedUnfairLock<Bool>`. The queued work checks `token.isCancelled` between files and
  between 64 KiB read chunks and throws `CancellationError` when set. The continuation is
  resumed exactly once, from the queue.
  - `@unchecked Sendable` justification: the only mutable state (the cache) is read and
    written exclusively on that serial queue; `root` and `fileManager` are immutable.
  - A hung blocking `read()` holds only this dedicated thread. Because the queue is serial,
    a later scan would queue behind it, but the coordinator never issues one while the
    previous worker is still running (Decision 8).
- **Fixed root.** The root is fixed by the composition root. `CLAUDE_CONFIG_DIR`, `$HOME`
  overrides and `~/.config/claude` are never consulted (spec section 2, A2).
- **Root checks.** The root is listed with `contentsOfDirectory(at:includingPropertiesForKeys:
  [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
  .attributeModificationDateKey, .fileResourceIdentifierKey, .isReadableKey])`.
  - The root is missing or not a directory → throw `RefreshFailure.noData`.
  - `EACCES`/`EPERM` (CocoaError `.fileReadNoPermission`) → throw
    `RefreshFailure.permissionDenied`.
  - Any other root error → throw `RefreshFailure.unreadableData`.
- **Which files are read.** Only depth 2 is read: each non-symlink directory directly
  under the root, and in it each non-symlink regular file whose extension is `jsonl`
  (case-sensitive). Subdirectories deeper down and symlinked entries are skipped, so no
  other location can be reached.
- **How files are read.** Files are opened read-only with
  `FileHandle(forReadingFrom:)`, read in 64 KiB chunks and split on `\n`. A trailing
  partial line is parsed (and usually rejected). Nothing is ever written, moved, renamed
  or deleted. Opening for reading leaves contents and modification times unchanged (spec
  section 2, last bullet).
- **Per-file errors.** If a file fails with a permission error, `permissionDeniedFileCount`
  goes up by one. Any other I/O error adds one to `unreadableFileCount`. The file is
  skipped and the scan continues.
- **Per-file cache (in memory only).** The cache is
  `[path: (FileFingerprint, UsageFileDigest)]` with
  `FileFingerprint = (size, contentModificationDate, attributeModificationDate (ctime),
  fileResourceIdentifier (inode))`.
  - A file is served from cache only if its fingerprint is unchanged **and**
    `isReadableKey` is true. A `chmod` changes ctime, and a replaced file changes the
    inode, so either forces a re-read. A file that is no longer readable is evicted and
    counted as permission denied, as if it had not been cached.
  - Entries for files that no longer exist are removed on every scan, so the cache is
    bounded by the files currently on disk.
  - Digests completed before a timeout/cancellation are kept, so a large first scan that
    times out makes progress toward the next one.
  - Within a file digest, `sessionId` and `cwd` strings are interned through a per-file
    dictionary to limit memory.
  - The cache is never persisted (spec section 8).

### 10. AppKit shell (`AIConsumeStatusBar`)
- **`main.swift`.** It creates `NSApplication.shared`, sets
  `setActivationPolicy(.accessory)` (no Dock icon, no window, even when run as a bare
  executable), installs `AppDelegate` and calls `run()`. The bundled app also sets
  `LSUIElement = true` in `Info.plist`.
- **`AppDelegate`** is the composition root and holds the only references. It builds
  `LocalClaudeProjectsSource(root: ~/.claude/projects)`, `TaskSleeper`, one clock closure
  `now = { Date() }`, `Calendar.current` with `TimeZone.current`, and `RefreshCoordinator`.
  It then creates `StatusBarController(coordinator:now:calendar:)` with the **same** `now`
  and `calendar`, and `WakeObserver`, and calls `startAutomaticRefresh()`. There are no
  singletons beyond AppKit's own `NSApplication.shared` / `NSStatusBar.system` /
  `NSWorkspace.shared`.
- **`StatusBarController`** (`@MainActor`, `NSMenuDelegate`):
  - `init(coordinator: RefreshCoordinator, now: @escaping @Sendable () -> Date, calendar: Calendar)`.
  - It creates exactly one `NSStatusItem(variableLength)`.
  - The button image is `NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
    accessibilityDescription: "Claude Code token usage")` with `isTemplate = true`, so
    macOS tints it for light and dark menu bars (A16). `imagePosition = .imageLeading`
    puts the icon left of the title.
  - `apply(_ model: MenuModel)` sets the button title. `menuNeedsUpdate(_:)` rebuilds the
    `NSMenu` from `MenuPresenter.render(coordinator.state, now: now(), calendar: calendar)`
    using the injected clock. This is synchronous and in memory, so opening the menu never
    waits for a refresh (spec section 4, last sentence).
  - `.info` and `.header` items have `action = nil` and `isEnabled = true`, with
    `menu.autoenablesItems = false`. They stay readable, and selecting them only closes
    the menu (A10).
  - `.action(.refreshNow)` calls `coordinator.refresh()`. `.action(.quit)` calls
    `NSApp.terminate(nil)`, and the status item disappears with the process.
- **Logging.** `os.Logger(subsystem: "dev.pablo.AIConsumeStatusBar", category: "refresh")`
  logs only the refresh outcome (`RefreshFailure.reason`, `.public`), the events "skipped:
  refresh in progress" and "late result discarded", counts (files, records, durations) and
  nothing else. It never logs a line, a path or a project name, and never any decoded
  string field.
- **No storage.** No `UserDefaults` keys are written and no Application Support files
  are created.

### 11. Packaging (personal use, spec "Out of scope": no signing/notarization)
- `scripts/build-app.sh` runs `swift build -c release`, assembles
  `build/AIConsumeStatusBar.app/Contents/{MacOS/AIConsumeStatusBar, Info.plist}` from
  `Resources/Info.plist` (`LSUIElement=true`, `LSMinimumSystemVersion=13.0`,
  `CFBundleIdentifier=dev.pablo.AIConsumeStatusBar`) and ad-hoc signs with `codesign -s -`.
- The app is not sandboxed and has no entitlements, in particular no
  `com.apple.security.network.client`.

### 12. Conventions this ADR establishes (to be copied into `repo-conventions` by the team)
The implementer and ac-tester stop with BLOCKED while these are TODO, and neither may
edit `.claude/`. **The tech lead must fill `repo-conventions` with these values at
TL_GATE, before IMPLEMENTATION starts.**

| Purpose | Command |
|---|---|
| Install deps | `swift package resolve` (no third-party dependencies; no-op today) |
| Build | `swift build` |
| Full test suite | `swift test` |
| Run tests in one folder (`tests/<id>/`) | `swift test --filter Acceptance_<id with "-" replaced by "_">` |
| Lint | `swift format lint --strict --recursive Package.swift Sources tests` |
| Format | `swift format --in-place --recursive Package.swift Sources tests` |
| Type check | covered by `swift build` |
| Build app bundle | `scripts/build-app.sh` |

- **Folders:** source in `Sources/<Target>/`, unit tests in `tests/unit/<Target>Tests/`,
  acceptance tests in `tests/<id>/`, ADRs in `docs/adr/NNNN-<slug>.md`.
- **Style:** `.swift-format` at the repo root, 4-space indent, line length 120.
- **Naming:** one type per file, file named after the type. Types in `UpperCamelCase`;
  functions and variables in `lowerCamelCase`.

### Dependencies added / removed
None added, none removed. Apple system frameworks only.

## Discarded alternatives
| Alternative | Why discarded |
|---|---|
| SwiftUI `MenuBarExtra` | The menu is rebuilt at open time from current state, and `NSMenuDelegate.menuNeedsUpdate` does that directly. `MenuBarExtra(.menu)` rebuilds through view diffing and gives less control over enabled/disabled informational items and the template icon + title layout. It would also need a SwiftUI `App` lifecycle. Both work without Xcode; AppKit is the smaller and more predictable surface. |
| Electron / Python `rumps` | Adds a runtime and third-party dependencies (against the guideline). Python `rumps` is unmaintained-ish and needs py2app for a bundle. Electron is ~150 MB for a menu item. The machine already has Swift 6.4. |
| Xcode project (`.xcodeproj`) | Xcode is not installed, and the workflow must build and test from the command line. |
| XCTest instead of Swift Testing | XCTest is not reliably available with Command Line Tools only. Swift Testing ships with the Swift 6 toolchain and supports parameterized tests for `Scenario Outline`. |
| Re-read and re-parse every file on every refresh (no cache) | Simplest. But with hundreds of MB of JSONL the 5-minute refresh would repeatedly burn CPU and risk the 15 s `timed out`. The fingerprint cache re-reads only changed files (normally the one or two active session files). |
| Persist the cache / aggregates to disk | Faster cold start, but it creates support files derived from local data (privacy surface, spec section 8) and an invalidation problem across app versions. The in-memory cache is enough for a long-running menu bar app. |
| Skip files whose mtime is before the month start | It would make the first scan cheaper. But spec 4.4 requires a session's start to be its earliest record in any period, and an earlier record can live in an older file. It also weakens A6b attribution. Rejected for correctness; the cache covers the cost after the first scan. |
| `FSEvents` file watching instead of a 5-minute poll | Not requested (triggers are fixed by spec section 5 / A11). Watching a busy folder while Claude Code streams would cause many refreshes. Could be revisited later. |
| Recursive enumeration of `~/.claude/projects` | Spec section 2 says "every `*.jsonl` file in every project folder directly under it". Recursion would read nested folders (e.g. sub-agent transcripts) and change the totals. |
| Dedup by first occurrence in directory-enumeration order | Enumeration order is not guaranteed, so attribution would be non-deterministic. Ordering files by their first record implements A6b exactly. |
| Floating-point rounding with `NumberFormatter` | Locale-dependent separators (A12 requires `.`) and binary rounding errors at boundaries such as 999 950. Integer arithmetic is exact. |
| Timeout by racing scan and sleep inside `withThrowingTaskGroup` (previous revision) | A task group cannot leave its scope until every child has finished; `cancelAll()` only requests cancellation. A scan that ignores cancellation (hung `read()`, never-resuming test source) would delay the `timed out` outcome indefinitely, violating spec section 5. Replaced by the independent timeout timer in Decision 8. |
| On timeout, release single flight immediately and let a new refresh start while the old worker still runs | Meets the 15 s rule but runs two scans at once (spec section 5: no second, parallel refresh), and with a serial I/O queue the new scan would just queue behind the hung one anyway. |
| Accept a late successful result after `timed out` was shown | The user would see `timed out` and then, unprompted, a success computed with a stale "now". Discarding keeps exactly one outcome per attempt; the source cache keeps the work, so the next refresh is fast. |
| Blocking file reads inside an `actor` on the cooperative pool (previous revision) | A hung read would pin one of the few cooperative-pool threads. A dedicated serial `DispatchQueue` isolates it. A custom actor executor on a `DispatchSerialQueue` needs macOS 14, above the chosen minimum. |
| Cache key of size + mtime only (previous revision) | A `chmod` that removes read permission changes only ctime, so the file would keep being served from cache instead of counting as permission denied. ctime + inode + `isReadable` close that gap at no extra I/O (same `stat`). |

## Consequences
- **Positive:**
  - All rules in spec sections 2-7 live in pure, AppKit-free `TokenUsageCore` functions
    that the acceptance tests drive directly with fixed "now", time zone and temp-dir
    data.
  - `timed out` is shown exactly when the timeout timer fires, regardless of whether the
    reading work honours cancellation, and single flight still holds.
  - There are no third-party dependencies and no network code.
  - Builds with `swift build` and Command Line Tools only.
  - The UI layer is thin (render model, forward two actions).
- **Negative / trade-offs:**
  - The first scan reads every JSONL file under the root.
  - The in-memory cache holds one small struct per valid usage record (about 100-150 bytes
    each). Around 100k records means about 10-15 MB of resident memory.
  - The format is undocumented (A3): a schema change in Claude Code silently drops records
    (they count as invalid lines) until the parser is updated. If nothing parses, the user
    sees `Update failed: unreadable data`.
  - While a timed-out worker has not exited, `Refresh now` does nothing visible (the error
    line stays). This is the price of single flight; it ends when the worker exits.
  - A late result that arrives after `timed out` is thrown away even if it was a success.
  - Without signing/notarization, Gatekeeper requires a manual "Open" the first time
    (accepted: personal use).
- **Risks and mitigations:**
  - *Timeout on a large first scan.* Mitigated by the `"usage"` byte pre-filter, decoding
    only the needed fields, cooperative cancellation via the scan token and the cache kept
    across timed-out scans. The next refresh then finishes from cache.
  - *A blocking `read()` on a hung volume ignores cancellation.* The timeout timer in
    Decision 8 applies `Update failed: timed out` at 15 s without waiting for the worker.
    The attempt (and `isRefreshing`) stays open until the worker exits, so no second scan
    starts; its late result is discarded. The hang occupies only the dedicated I/O thread
    (Decision 9). If the read never returns, the app keeps showing stale values with
    `timed out` until relaunch; this is logged.
  - *Swift Testing or `swift format` missing from the installed toolchain.* Both ship with
    Swift 6.x toolchains. If either is missing, the implementer reports BLOCKED and does
    not substitute a tool.
  - *`tests/` vs `Tests/` case collision.* Only lowercase `tests/` is used.
  - *Acceptance target folder empty at first build.* SwiftPM fails on a declared target
    with no sources. The tech lead decides at TL_GATE whether ac-tester's files exist
    before IMPLEMENTATION, or how the implementer's build handles the gap; the implementer
    must not write into `tests/<id>/` (process decision, out of this ADR's authority).
  - *Process risk.* `repo-conventions` is still TODO, and ac-tester only sees spec.md,
    acceptance.feature and what exists on `main` (nothing yet). It may BLOCK for lack of a
    test seam. Mitigation: the tech lead fills `repo-conventions` from Decision section 12
    at TL_GATE. The public interfaces in Decision section 3 (including `waitForOutcome()`)
    are the seam the acceptance tests should use. The orchestrator may need to pass adr.md
    section 3 to ac-tester (process decision, out of this ADR's authority).
- **Security considerations:**
  - No network code, no networking frameworks imported, no network entitlement, so the
    attack surface is local files only.
  - Input is untrusted JSONL from disk:
    - It is decoded with `JSONDecoder` into explicit types with only numeric, date and
      short string fields.
    - Lines are processed one at a time, so a huge or malformed line cannot crash the app.
      Decoding errors return `nil`.
    - Token values are validated as non-negative integers.
    - Sums use `Int` (64-bit), so overflow is not reachable with realistic data. The
      aggregator uses `addingReportingOverflow` and saturates at `Int.max` instead of
      trapping.
  - Path handling: the only root is fixed and depth is limited to 2. Symlinks are skipped
    and no path is built from file contents, so there is no traversal.
  - Revoked read permission is detected even for cached files (ctime/inode fingerprint +
    `isReadable`), so cached content is not served after access is withdrawn.
  - Project names from `cwd` are shown as plain `NSMenuItem` titles (no HTML or format
    strings).
  - Nothing is written: no secrets, credentials, preferences, cache files or content in
    logs. `os.Logger` gets only failure reasons, fixed event names and counts.
- **Performance considerations:**
  - I/O and parsing run on a dedicated serial utility queue; aggregation runs in a detached
    utility task. The main thread only applies state and renders the menu (O(1), at most 17
    lines).
  - Refreshes run at most once per 5 minutes plus manual and wake triggers, with single
    flight. A hung worker never multiplies: at most one scan exists at any time.
  - Aggregation is O(N) over cached records with hash sets/maps. The session sort is
    O(S log S) and the file sort O(F log F).
  - The cache check reuses the directory listing's resource values (one `stat` per file);
    adding ctime/inode/readability costs no extra I/O.
  - Changed files are re-read in full (append-only files only grow; a tail-offset
    optimization is possible later if measurements need it).
  - The cache is bounded by the files on disk and pruned every scan. The loop task, timeout
    timer, worker and wake observer are cancelled or removed on `stop()` and at termination.

## Impact on acceptance criteria
Test seam used below: "pure path" means `UsageRecordParser`/`UsageAggregator`/`MenuPresenter`/`CompactNumberFormatter`, or `RefreshCoordinator` with `LocalClaudeProjectsSource(root: <temp dir>)` or a fake `UsageSource`, injected `now`, `Calendar` (fixed time zone) and a controllable `Sleeper`, waiting with `waitForOutcome()` / `waitForIdle()` and asserting on `MenuPresenter.render(...)` (`title`, `lines.compactMap(\.text)`).

| Scenario | Satisfied by |
|---|---|
| App appears only in the menu bar on launch | Decision 10: one `NSStatusItem`, `setActivationPolicy(.accessory)` + `LSUIElement=true`, no window created. Verified by QA on the built app. Unit level: `AppDelegate` creates exactly one status item. |
| Quit removes the menu bar item | Decision 7 (`.action("Quit", .quit)`) + Decision 10 (`NSApp.terminate`); the status item goes away with the process. |
| Title shows this month's total tokens | Decision 5 (period totals) + 6 (`12.5k`) + 7 (title format). |
| Menu bar item shows an icon before the title | Decision 7 (`iconSymbolName`, `iconIsTemplate`) + 10 (`imagePosition = .imageLeading`, SF Symbol). |
| Icon stays visible in both menu bar appearances (Light, Dark) | Decision 10: template SF Symbol, which macOS tints for the current appearance (A16). `MenuModel.iconIsTemplate == true` is assertable; visual check by QA. |
| Compact token formatting (all 7 rows) | Decision 6 integer algorithm; title and menu total share the formatter (Decision 7). |
| Title while the first refresh is in progress | Decision 7: no `lastSuccess` and no failure → `…`, `Total this month: —`, no breakdown lines, `No data yet`. Decision 8: a fake source that does not return and a sleeper that does not release the 15 s timeout keep the first attempt undecided; `state` is read right after `startAutomaticRefresh()`. |
| Menu shows the total divided by token type | Decision 3 `TokenCounts` + 5 (per-type sums) + 7 (line order). |
| Token types are added up across all records of the month | Decision 5 step 3 + 6 (`1.5k`, `2.5k`, `3k`, `1.5M`). |
| Missing token fields count as zero | Decision 4 (missing fields → 0) + 7. |
| Usage from earlier days of the current month is counted | Decision 3 `ReportingPeriod.currentMonth` (start = day 1 00:00 local) + 5. |
| Usage from previous months is not counted | Decision 5 step 3 (`period.contains`). |
| Total starts over at the start of a new month | Decision 8: period recomputed from `now()` at each attempt; Decision 5. |
| A session that spans the month boundary counts only this month's tokens | Decision 5 steps 2-3: `start` from any period (`30/09/2026 23:30`), tokens only in period; Decision 6 date format. Fixture records carry `cwd` ending in `alpha` (spec 4.4 defines `<project>` from `cwd`). |
| Records with a future timestamp are ignored | Decision 3 `ReportingPeriod.end = now`, Decision 5 step 3. |
| Duplicate usage records are counted once | Decision 5 step 1 (global `responseKey` dedup, A6/A6b attribution to one session). |
| Records in every project folder are counted | Decision 9: every directory directly under the root. |
| Only ~/.claude/projects is read | Decision 9: fixed root injected by composition root; `CLAUDE_CONFIG_DIR` and `~/.config/claude` never consulted. Test: source on a temp root + env var set; only root data counted. |
| Records without a session identifier count in the total but are not ranked | Decision 4 (empty/absent `sessionId` → nil) + 5 steps 3-4. |
| Menu shows total, breakdown, top sessions, last update and actions | Decision 7 line order (separators carry no text) + 6 (`6.3M`, `290k`, `1M`, `4M`, `4.2M`, `1.3M`, `840k`) + `Updated HH:mm` from `completedAt`. |
| Only the 5 sessions with the most tokens are listed | Decision 5 step 4 (sort, take 5). |
| Fewer than 5 sessions this month | Decision 5 step 4 + 7 (only existing sessions). |
| Sessions with equal tokens are ordered by most recent activity | Decision 5 step 4 second key (`lastActivity` desc). |
| Sessions with equal tokens and equal last activity are ordered by session identifier | Decision 5 step 4 third key (`sessionId` asc). |
| Session with no recorded working directory | Decision 3 `projectName == nil` → Decision 7 renders `Unknown project`. |
| Selecting a session line does nothing | Decision 7 (`.info` has no action) + 10 (`action = nil`, no window, no `NSWorkspace.open`). |
| Last successful update on an earlier day shows its date | Decision 6 `updated(_:now:)` + 7 (rendered with the injected `now` at menu-open time, Decision 10); Decision 8 keeps `lastSuccess` on failure. |
| No Claude Code usage this month | Decision 5 step 5 (valid records exist → success with zero totals) + 7 (`0` lines, `No sessions this month`, no failure line). |
| Claude Code data folder exists but holds no files | Decision 9 (empty root → empty scan) + 5 step 5 last bullet (success, zeros). |
| No Claude Code data on this Mac | Decision 9 (missing root → `.noData`) + 7 (`—` title, `Total this month: —`, no breakdown, `No data yet`, `Update failed: no Claude Code data found`). |
| Automatic refresh every 5 minutes | Decision 8 loop with `autoRefreshInterval = 300 s` (controllable sleeper in tests) + `Updated` from `completedAt`. |
| Manual refresh | Decision 7 `.refreshNow` → `RefreshCoordinator.refresh()`; Decision 9 cache re-reads the changed file (fingerprint changed). |
| Refresh on wake from sleep | Decision 8/10 `WakeObserver` (`NSWorkspace.didWakeNotification`) → `refresh()`. |
| Manual refresh while a refresh is in progress | Decision 8 single flight: `refresh()` returns while `attempt != nil` (including the post-timeout window); a fake source counts concurrent `scan()` calls and the test asserts the maximum is 1. |
| Menu opens while a refresh is in progress | Decision 7/10: `menuNeedsUpdate` renders in-memory state synchronously; no await. |
| Malformed records are skipped and the rest still count | Decision 4 (invalid line → nil) + 5 step 5 (valid records → success). |
| No readable usage record at all | Decision 5 step 5 (`.unreadableData`) + 7 (`—`, `Update failed: unreadable data`); Decision 8 (failure applied, no crash). |
| Reading local data times out | Decision 8 independent timeout timer: when the injected `Sleeper` releases the 15 s sleep, `timeoutFired` sets `currentFailure = .timedOut` and calls `onStateChange` without waiting for the worker. Test: fake source that never returns (ignores cancellation), release the timeout, `await waitForOutcome()`, assert `Update failed: timed out`. Works equally with a source that honours cancellation. |
| Failure with a previous reading keeps the stale values | Decision 8 (failure and timeout keep `lastSuccess`) + 7. "Has since become unreadable" is reproduced by replacing the data with lines that are not valid usage records, which spec section 7 maps to `unreadable data`. Revoking read permission maps to `permission denied` by the spec's own table (detected even for cached files, Decision 9). |
| Successful refresh after a failure clears the error | Decision 8 (a new attempt's success sets `currentFailure = nil`, including after `timed out` once the earlier worker has exited) + 7. |
| Permission denied reading Claude Code data | Decision 9 (root `EACCES`/`EPERM` → `.permissionDenied`; per-file denials counted, including cached files that became unreadable) + 5 step 5 + 7. |
| The app makes no network requests | Decision 1/10/11: no networking API used or imported, no network entitlement. Verifiable statically (no `URLSession`/`Network`/`CFNetwork` symbols in `Sources/`) and at runtime by QA (`nettop`/`lsof -i` on the running app). |
| Conversation content is never copied out of the local data | Decision 4 (content is never decoded), 9 (cache in memory only, never persisted), 10 (no `UserDefaults`, no support files, logs only reasons/event names/counts). |
| Conversation content is never shown in the menu | Decision 4 + 7: menu lines are built only from counts, dates, session ids and `cwd` last components. |
| Local Claude Code data is never modified | Decision 9: read-only `FileHandle`, no write/move/delete APIs used on the root. |

No CONFLICT.

## Files expected to change
- `Package.swift` — new: targets `TokenUsageCore`, `TokenUsageData`, `AIConsumeStatusBar` (executable), `TokenUsageCoreTests` and `TokenUsageDataTests` (paths under `tests/unit/`), and `Acceptance_req_20261015_macos_status_bar_token_usage` (path `tests/req-20261015-macos-status-bar-token-usage/`); platform macOS 13; Swift 6 language mode.
- `.swift-format` — new: formatter/linter configuration (Decision 12).
- `.gitignore` — add `.build/` and `build/`.
- `Sources/TokenUsageCore/TokenCounts.swift` — new: per-type counts and total.
- `Sources/TokenUsageCore/UsageRecord.swift` — new: parsed record model.
- `Sources/TokenUsageCore/UsageRecordParser.swift` — new: lenient line parser (Decision 4).
- `Sources/TokenUsageCore/UsageScan.swift` — new: `UsageFileDigest`, `UsageScan`.
- `Sources/TokenUsageCore/UsageSource.swift` — new: `UsageSource` protocol.
- `Sources/TokenUsageCore/RefreshFailure.swift` — new: failure enum and reason strings.
- `Sources/TokenUsageCore/ReportingPeriod.swift` — new: current-month period.
- `Sources/TokenUsageCore/UsageAggregator.swift` — new: dedup, totals, sessions, classification (Decision 5).
- `Sources/TokenUsageCore/SessionSummary.swift` — new: session model.
- `Sources/TokenUsageCore/UsageSnapshot.swift` — new: snapshot model.
- `Sources/TokenUsageCore/CompactNumberFormatter.swift` — new: compact numbers (Decision 6).
- `Sources/TokenUsageCore/DisplayDateFormatter.swift` — new: `dd/MM/yyyy HH:mm` / `HH:mm`.
- `Sources/TokenUsageCore/AppState.swift` — new: `AppState`, `SuccessfulRefresh`.
- `Sources/TokenUsageCore/MenuModel.swift` — new: `MenuModel`, `MenuLine`, `MenuAction`.
- `Sources/TokenUsageCore/MenuPresenter.swift` — new: title and menu lines (Decision 7).
- `Sources/TokenUsageCore/Sleeper.swift` — new: `Sleeper` protocol.
- `Sources/TokenUsageCore/RefreshCoordinator.swift` — new: attempts, single flight, independent timeout timer, late-result discard, triggers, test waiters (Decision 8).
- `Sources/TokenUsageData/LocalClaudeProjectsSource.swift` — new: read-only scanner on a dedicated serial I/O queue + in-memory fingerprint cache (Decision 9).
- `Sources/TokenUsageData/ScanCancellation.swift` — new: lock-backed cancellation flag bridged from Swift task cancellation to the I/O queue.
- `Sources/TokenUsageData/LineReader.swift` — new: 64 KiB chunked line splitting with cancellation checks.
- `Sources/AIConsumeStatusBar/main.swift` — new: app bootstrap, `.accessory` policy.
- `Sources/AIConsumeStatusBar/AppDelegate.swift` — new: composition root (single shared `now` clock and calendar).
- `Sources/AIConsumeStatusBar/StatusBarController.swift` — new: `NSStatusItem`, icon, `NSMenuDelegate` rendering with the injected clock.
- `Sources/AIConsumeStatusBar/WakeObserver.swift` — new: wake-from-sleep trigger.
- `Sources/AIConsumeStatusBar/TaskSleeper.swift` — new: production `Sleeper`.
- `Resources/Info.plist` — new: `LSUIElement`, bundle id, minimum system version.
- `scripts/build-app.sh` — new: assembles and ad-hoc signs `build/AIConsumeStatusBar.app`.
- `tests/unit/TokenUsageCoreTests/*.swift` — new: implementer unit tests for core (including timeout with a non-cancellable fake source, late-result discard, triggers dropped in the post-timeout window).
- `tests/unit/TokenUsageDataTests/*.swift` — new: implementer unit tests for the file-system adapter (temp directories, cache invalidation on chmod/replace).
- `tests/req-20261015-macos-status-bar-token-usage/*.swift` — new, owned by ac-tester (listed for completeness; the implementer does not touch it).
- `docs/adr/0001-macos-status-bar-token-usage.md` — new: this ADR, copied when accepted (proposed ADR location from `repo-conventions`).
- `.claude/skills/repo-conventions/SKILL.md` — NOT changed by the implementer (forbidden). The tech lead fills the TODOs from Decision 12 before IMPLEMENTATION.

## Review feedback addressed
| Requested change (arch-review.md) | What changed |
|---|---|
| 1. Timeout must report `timed out` at 15 s without depending on the worker exiting; remove the contradiction between Decision 8 and Consequences > Risks; state what happens to `inFlight`/`isRefreshing`, triggers and a late result until the worker exits. | Decision 8 rewritten. The `withThrowingTaskGroup` race is removed. Each refresh is an `Attempt` with an id, a detached worker task and an independent main-actor timeout timer. `timeoutFired(id:)` applies `currentFailure = .timedOut`, calls `onStateChange` (so `Update failed: timed out` shows) and cancels the worker, all without awaiting the worker. `attempt` (single flight) and `isRefreshing` stay set until `workerExited(id:result:)` runs. Triggers in that window are dropped. A late result (success or failure) is discarded and logged. `outcomeApplied` plus the id check guarantee one outcome per attempt. A table "Behavior while a timed-out worker has not exited" states each aspect, including a worker that never exits. Consequences > Risks bullet rewritten to match Decision 8 exactly. Added `waitForOutcome()` test seam (Decision 3) because `waitForIdle()` never returns with a non-cancellable source. Context gained a "Timeout vs. single flight" force. Discarded alternatives gained rows for the task-group race, releasing single flight on timeout and accepting late results. AC rows "Reading local data times out", "Title while the first refresh is in progress", "Manual refresh while a refresh is in progress" and "Successful refresh after a failure clears the error" updated. |
| Note (optional): cache keyed on size + mtime misses `chmod`. | Adopted. Decision 9 fingerprint adds ctime (`attributeModificationDateKey`) and inode (`fileResourceIdentifierKey`), and a cached file is served only if `isReadableKey` is true; otherwise it is evicted and counted as permission denied. |
| Note (optional): blocking reads inside an actor hold a cooperative-pool thread. | Adopted. Decision 9: `LocalClaudeProjectsSource` runs all file I/O on a dedicated serial `DispatchQueue`, bridged with a continuation and a lock-backed cancellation token. Custom actor executor discarded (needs macOS 14). |
| Note (optional): `menuNeedsUpdate` uses `Date()` instead of the injected clock. | Adopted. Decision 10: `StatusBarController(coordinator:now:calendar:)` receives the same `now` and `calendar` as the coordinator. |
| Note (optional): acceptance target folder may be empty at first build. | Recorded as a TL_GATE process risk in Consequences > Risks and in Decision 2; not decided here (out of this ADR's authority). |
| Notes (optional): repo-conventions/ac-tester seam; "has since become unreadable" reading. | No design change needed; the existing process-risk bullet now also names `waitForOutcome()` as part of the seam. |
