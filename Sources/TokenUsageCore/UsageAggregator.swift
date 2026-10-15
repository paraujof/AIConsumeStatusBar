import Foundation

public enum UsageAggregator {
    private struct Accumulator {
        var start: Date
        var cwdTimestamp: Date?
        var cwd: String?
        var lastActivity: Date?
        var tokens = 0
    }

    public static func aggregate(_ scan: UsageScan, period: ReportingPeriod) -> Result<UsageSnapshot, RefreshFailure> {
        let ordered = scan.files.sorted { a, b in
            switch (a.records.first?.timestamp, b.records.first?.timestamp) {
            case (let x?, let y?): return x != y ? x < y : a.path < b.path
            case (nil, nil): return a.path < b.path
            case (nil, _): return false
            case (_, nil): return true
            }
        }

        var seen = Set<String>()
        var totals = TokenCounts.zero
        var sessions: [String: Accumulator] = [:]
        var validCount = 0

        for file in ordered {
            for record in file.records {
                validCount += 1
                if let key = record.responseKey {
                    if !seen.insert(key).inserted { continue }
                }
                let inPeriod = period.contains(record.timestamp)
                if inPeriod { totals.accumulate(record.tokens) }
                guard let sid = record.sessionId else { continue }
                var acc = sessions[sid] ?? Accumulator(start: record.timestamp)
                if record.timestamp < acc.start { acc.start = record.timestamp }
                if let cwd = record.cwd, acc.cwdTimestamp == nil || record.timestamp < acc.cwdTimestamp! {
                    acc.cwd = cwd
                    acc.cwdTimestamp = record.timestamp
                }
                if inPeriod {
                    acc.tokens = TokenCounts.add(acc.tokens, record.tokens.total)
                    if acc.lastActivity == nil || record.timestamp > acc.lastActivity! {
                        acc.lastActivity = record.timestamp
                    }
                }
                sessions[sid] = acc
            }
        }

        if validCount == 0 {
            if scan.permissionDeniedFileCount > 0 { return .failure(.permissionDenied) }
            if scan.unreadableFileCount > 0 || scan.files.contains(where: { $0.nonEmptyLineCount > 0 }) {
                return .failure(.unreadableData)
            }
            return .success(UsageSnapshot(totals: .zero, topSessions: []))
        }

        let summaries =
            sessions
            .compactMap { (sid, acc) -> SessionSummary? in
                guard acc.tokens > 0, let last = acc.lastActivity else { return nil }
                return SessionSummary(
                    sessionId: sid,
                    projectName: acc.cwd.flatMap(projectName(fromCwd:)),
                    start: acc.start,
                    lastActivity: last,
                    tokens: acc.tokens
                )
            }
            .sorted { a, b in
                if a.tokens != b.tokens { return a.tokens > b.tokens }
                if a.lastActivity != b.lastActivity { return a.lastActivity > b.lastActivity }
                return Array(a.sessionId.utf8).lexicographicallyPrecedes(Array(b.sessionId.utf8))
            }
        return .success(UsageSnapshot(totals: totals, topSessions: Array(summaries.prefix(5))))
    }

    private static func projectName(fromCwd cwd: String) -> String? {
        let last = cwd.split(separator: "/", omittingEmptySubsequences: true).last
        return last.map(String.init)
    }
}
