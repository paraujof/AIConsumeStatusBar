import Foundation

public enum MenuPresenter {
    public static let iconSymbolName = "gauge.with.dots.needle.33percent"

    public static func render(_ state: AppState, now: Date, calendar: Calendar) -> MenuModel {
        let fmt = CompactNumberFormatter.string
        let dates = DisplayDateFormatter(calendar: calendar)
        let success = state.lastSuccess

        let title: String
        if let success {
            title = "Claude total: \(fmt(success.snapshot.totals.total)) tokens"
        } else if state.currentFailure != nil {
            title = "Claude total: \u{2014} tokens"
        } else {
            title = "Claude total: \u{2026} tokens"
        }

        var lines: [MenuLine] = []
        if let success {
            let t = success.snapshot.totals
            lines.append(.info("Total this month: \(fmt(t.total)) tokens"))
            lines.append(.info("Input: \(fmt(t.input))"))
            lines.append(.info("Output: \(fmt(t.output))"))
            lines.append(.info("Cache write: \(fmt(t.cacheCreation))"))
            lines.append(.info("Cache read: \(fmt(t.cacheRead))"))
        } else {
            lines.append(.info("Total this month: \u{2014}"))
        }
        lines.append(.separator)
        lines.append(.header("Top sessions this month"))
        if let success {
            let sessions = success.snapshot.topSessions
            if sessions.isEmpty {
                lines.append(.info("No sessions this month"))
            }
            for (i, s) in sessions.enumerated() {
                let name = s.projectName ?? "Unknown project"
                lines.append(.info("\(i + 1). \(name) \u{00B7} \(dates.dateTime(s.start)) \u{00B7} \(fmt(s.tokens))"))
            }
        }
        lines.append(.separator)
        if let success {
            lines.append(.info("Updated \(dates.updated(success.completedAt, now: now))"))
        } else {
            lines.append(.info("No data yet"))
        }
        if let failure = state.currentFailure {
            lines.append(.info("Update failed: \(failure.reason)"))
        }
        lines.append(.separator)
        lines.append(.action("Refresh now", .refreshNow))
        lines.append(.action("Quit", .quit))

        return MenuModel(title: title, iconSymbolName: iconSymbolName, iconIsTemplate: true, lines: lines)
    }
}
