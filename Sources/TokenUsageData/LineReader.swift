import Foundation

/// Reads a file in 64 KiB chunks and hands each `\n`-terminated line (and a trailing partial line) to `body`.
enum LineReader {
    static let chunkSize = 64 * 1024

    static func forEachLine(
        in url: URL,
        cancellation: ScanCancellation,
        _ body: (Data) -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        while true {
            if cancellation.isCancelled { throw CancellationError() }
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            pending.append(chunk)
            var lineStart = pending.startIndex
            var searchFrom = pending.endIndex - chunk.count
            while let newline = pending[searchFrom...].firstIndex(of: 0x0A) {
                body(Data(pending[lineStart..<newline]))
                lineStart = newline + 1
                searchFrom = lineStart
            }
            if lineStart != pending.startIndex {
                pending = Data(pending[lineStart...])
            }
        }
        if !pending.isEmpty { body(pending) }
    }
}
