public struct TokenCounts: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    public var total: Int {
        TokenCounts.add(TokenCounts.add(input, output), TokenCounts.add(cacheCreation, cacheRead))
    }

    public static let zero = TokenCounts()

    /// Saturating addition (never traps).
    static func add(_ a: Int, _ b: Int) -> Int {
        let (value, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : value
    }

    mutating func accumulate(_ other: TokenCounts) {
        input = TokenCounts.add(input, other.input)
        output = TokenCounts.add(output, other.output)
        cacheCreation = TokenCounts.add(cacheCreation, other.cacheCreation)
        cacheRead = TokenCounts.add(cacheRead, other.cacheRead)
    }
}
