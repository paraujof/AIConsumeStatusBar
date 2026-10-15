import Foundation
import Testing
import TokenUsageCore

@testable import TokenUsageData

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tud-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func line(_ ts: String, _ input: Int, session: String = "s-1") -> String {
    "{\"timestamp\":\"\(ts)\",\"sessionId\":\"\(session)\",\"cwd\":\"/p/alpha\",\"message\":{\"id\":\"m\(input)\",\"usage\":{\"input_tokens\":\(input)}},\"requestId\":\"r\"}\n"
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

@Suite struct LocalClaudeProjectsSourceTests {
    @Test func missingRootIsNoData() async throws {
        let src = LocalClaudeProjectsSource(
            root: FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID())"))
        await #expect(throws: RefreshFailure.noData) { try await src.scan() }
    }

    @Test func emptyRootGivesEmptyScan() async throws {
        let root = try makeRoot()
        let scan = try await LocalClaudeProjectsSource(root: root).scan()
        #expect(scan.files.isEmpty)
    }

    @Test func readsDepthTwoJsonlOnlyAndSkipsGarbage() async throws {
        let root = try makeRoot()
        try write(line("2026-10-15T09:00:00Z", 5) + "garbage\n\n", to: root.appendingPathComponent("alpha/a.jsonl"))
        try write(line("2026-10-15T09:00:00Z", 7), to: root.appendingPathComponent("beta/b.jsonl"))
        try write(line("2026-10-15T09:00:00Z", 9), to: root.appendingPathComponent("beta/deeper/c.jsonl"))
        try write(line("2026-10-15T09:00:00Z", 9), to: root.appendingPathComponent("beta/d.txt"))
        try write(line("2026-10-15T09:00:00Z", 9), to: root.appendingPathComponent("top.jsonl"))
        let scan = try await LocalClaudeProjectsSource(root: root).scan()
        #expect(scan.files.count == 2)
        let a = try #require(scan.files.first { $0.path.hasSuffix("alpha/a.jsonl") })
        #expect(a.records.count == 1)
        #expect(a.nonEmptyLineCount == 2)
    }

    @Test func handlesLongLinesAcrossChunks() async throws {
        let root = try makeRoot()
        let big = "{\"x\":\"" + String(repeating: "a", count: 300_000) + "\"}\n"
        try write(big + line("2026-10-15T09:00:00Z", 5), to: root.appendingPathComponent("alpha/a.jsonl"))
        let scan = try await LocalClaudeProjectsSource(root: root).scan()
        #expect(scan.files[0].records.count == 1)
        #expect(scan.files[0].nonEmptyLineCount == 2)
    }

    @Test func cacheSeesAppendedData() async throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("alpha/a.jsonl")
        try write(line("2026-10-15T09:00:00Z", 5), to: file)
        let src = LocalClaudeProjectsSource(root: root)
        #expect(try await src.scan().files[0].records.count == 1)
        let h = try FileHandle(forWritingTo: file)
        try h.seekToEnd()
        try h.write(contentsOf: Data(line("2026-10-15T09:05:00Z", 6).utf8))
        try h.close()
        #expect(try await src.scan().files[0].records.count == 2)
    }

    @Test func replacedFileWithSameSizeAndMtimeIsReRead() async throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("alpha/a.jsonl")
        try write(line("2026-10-15T09:00:00Z", 5), to: file)
        let mtime = try #require(
            try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        let src = LocalClaudeProjectsSource(root: root)
        #expect(try await src.scan().files[0].records[0].tokens.input == 5)
        let other = root.appendingPathComponent("alpha/other.tmp")
        try write(line("2026-10-15T09:00:00Z", 6), to: other)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: other.path)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: other)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        #expect(try await src.scan().files[0].records[0].tokens.input == 6)
    }

    @Test func revokedPermissionIsDetectedEvenWhenCached() async throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("alpha/a.jsonl")
        try write(line("2026-10-15T09:00:00Z", 5), to: file)
        let src = LocalClaudeProjectsSource(root: root)
        _ = try await src.scan()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let scan = try await src.scan()
        #expect(scan.permissionDeniedFileCount == 1)
        #expect(scan.files.isEmpty)
    }

    @Test func doesNotModifyFiles() async throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("alpha/a.jsonl")
        try write(line("2026-10-15T09:00:00Z", 5), to: file)
        let before = try Data(contentsOf: file)
        let mtime = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        _ = try await LocalClaudeProjectsSource(root: root).scan()
        #expect(try Data(contentsOf: file) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == mtime)
    }
}
