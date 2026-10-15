public struct UsageFileDigest: Equatable, Sendable {
    public let path: String
    public let records: [UsageRecord]
    public let nonEmptyLineCount: Int

    public init(path: String, records: [UsageRecord], nonEmptyLineCount: Int) {
        self.path = path
        self.records = records
        self.nonEmptyLineCount = nonEmptyLineCount
    }
}

public struct UsageScan: Equatable, Sendable {
    public let files: [UsageFileDigest]
    public let permissionDeniedFileCount: Int
    public let unreadableFileCount: Int

    public init(files: [UsageFileDigest], permissionDeniedFileCount: Int = 0, unreadableFileCount: Int = 0) {
        self.files = files
        self.permissionDeniedFileCount = permissionDeniedFileCount
        self.unreadableFileCount = unreadableFileCount
    }
}
