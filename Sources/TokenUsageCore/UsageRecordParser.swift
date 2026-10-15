import Foundation

public enum UsageRecordParser {
    private static let marker = Data("\"usage\"".utf8)

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let inputTokens: Int?
                let outputTokens: Int?
                let cacheCreationInputTokens: Int?
                let cacheReadInputTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                }
            }
            let id: String?
            let usage: Usage?
        }
        let timestamp: String?
        let sessionId: String?
        let cwd: String?
        let requestId: String?
        let message: Message?
    }

    /// Returns nil for anything that is not a valid usage record (spec section 2).
    public static func parse(line: Data) -> UsageRecord? {
        guard line.range(of: marker) != nil else { return nil }
        guard let decoded = try? JSONDecoder().decode(Line.self, from: line) else { return nil }
        guard let usage = decoded.message?.usage, let rawTimestamp = decoded.timestamp,
            let timestamp = parseDate(rawTimestamp)
        else { return nil }
        let values = [
            usage.inputTokens, usage.outputTokens, usage.cacheCreationInputTokens, usage.cacheReadInputTokens,
        ]
        if values.contains(where: { ($0 ?? 0) < 0 }) { return nil }
        let tokens = TokenCounts(
            input: usage.inputTokens ?? 0,
            output: usage.outputTokens ?? 0,
            cacheCreation: usage.cacheCreationInputTokens ?? 0,
            cacheRead: usage.cacheReadInputTokens ?? 0
        )
        var key: String?
        if let messageId = decoded.message?.id, let requestId = decoded.requestId, !messageId.isEmpty,
            !requestId.isEmpty
        {
            key = "\(messageId):\(requestId)"
        }
        return UsageRecord(
            timestamp: timestamp,
            sessionId: nonEmpty(decoded.sessionId),
            cwd: nonEmpty(decoded.cwd),
            responseKey: key,
            tokens: tokens
        )
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private static func parseDate(_ s: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let d = try? withFraction.parse(s) { return d }
        return try? Date.ISO8601FormatStyle().parse(s)
    }
}
