import Foundation

public struct ReportingPeriod: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public static func currentMonth(now: Date, calendar: Calendar) -> ReportingPeriod {
        let comps = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: comps) ?? now
        return ReportingPeriod(start: start, end: now)
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date <= end
    }
}
