import Foundation

public struct DisplayDateFormatter: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    public func dateTime(_ date: Date) -> String {
        format(date, "dd/MM/yyyy HH:mm")
    }

    public func updated(_ at: Date, now: Date) -> String {
        calendar.isDate(at, inSameDayAs: now) ? format(at, "HH:mm") : dateTime(at)
    }
}
