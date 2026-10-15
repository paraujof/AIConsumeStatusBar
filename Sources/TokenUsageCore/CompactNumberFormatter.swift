public enum CompactNumberFormatter {
    public static func string(_ value: Int) -> String {
        if value < 1_000 { return "\(value)" }
        let units: [(Int, String)] = [(1_000, "k"), (1_000_000, "M"), (1_000_000_000, "B")]
        var index = value >= 1_000_000_000 ? 2 : (value >= 1_000_000 ? 1 : 0)
        func tenths(_ i: Int) -> Int {
            let unit = units[i].0
            let (sum, overflow) = value.addingReportingOverflow(unit / 20)
            return (overflow ? Int.max : sum) / (unit / 10)
        }
        var t = tenths(index)
        if t >= 10_000 && index < 2 {
            index += 1
            t = tenths(index)
        }
        var s = "\(t / 10)"
        if t % 10 != 0 { s += ".\(t % 10)" }
        return s + units[index].1
    }
}
