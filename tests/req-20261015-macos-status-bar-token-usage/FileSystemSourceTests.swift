import Foundation
import Testing

@testable import TokenUsageCore
@testable import TokenUsageData

/// Real-filesystem tests through the injected root of `LocalClaudeProjectsSource`.
@Suite("Local file system source", .serialized)
struct FileSystemSourceTests {

    /// A temporary fake home folder; `projects` plays the role of "~/.claude/projects".
    private struct FakeHome {
        let home: URL
        var projects: URL { home.appendingPathComponent(".claude/projects", isDirectory: true) }

        init() throws {
            home = FileManager.default.temporaryDirectory
                .appendingPathComponent("ac-fs-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: projects.path)
            try? FileManager.default.removeItem(at: home)
        }

        @discardableResult
        func write(_ lines: [Data], folder: String, file: String = "session.jsonl", under base: URL? = nil) throws
            -> URL
        {
            let dir = (base ?? projects).appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var data = Data()
            for line in lines {
                data.append(line)
                data.append(0x0A)
            }
            let url = dir.appendingPathComponent(file)
            try data.write(to: url)
            return url
        }
    }

    private func total(_ scan: UsageScan) throws -> Int {
        try aggregateScan(scan, now: "2026-10-15 10:00").get().totals.total
    }

    // ---------- Only ~/.claude/projects is read ----------

    @Test("Only ~/.claude/projects is read")
    func onlyClaudeProjectsIsRead() async throws {
        let fake = try FakeHome()
        defer { fake.remove() }
        try fake.write([jsonLine("2026-10-15 09:00", session: "s-1", input: 200)], folder: "alpha")

        // "~/.config/claude/projects" next to it, with 100 tokens.
        let configProjects = fake.home.appendingPathComponent(".config/claude/projects", isDirectory: true)
        try fake.write(
            [jsonLine("2026-10-15 09:00", session: "s-2", input: 100)], folder: "beta", under: configProjects)

        // A CLAUDE_CONFIG_DIR whose "projects" folder has 50 tokens.
        let envDir = fake.home.appendingPathComponent("custom-claude", isDirectory: true)
        try fake.write(
            [jsonLine("2026-10-15 09:00", session: "s-3", input: 50)], folder: "gamma",
            under: envDir.appendingPathComponent("projects", isDirectory: true))

        let previous = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        setenv("CLAUDE_CONFIG_DIR", envDir.path, 1)
        defer {
            if let previous { setenv("CLAUDE_CONFIG_DIR", previous, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") }
        }

        let scan = try await LocalClaudeProjectsSource(root: fake.projects).scan()
        #expect(try total(scan) == 200)
        let paths = scan.files.map(\.path)
        #expect(!paths.isEmpty)
        let rootPath = fake.projects.resolvingSymlinksInPath().path
        #expect(paths.allSatisfy { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(rootPath) })
        #expect(!paths.contains { $0.contains(".config/claude") || $0.contains("custom-claude") })
    }

    // ---------- Local Claude Code data is never modified ----------

    @Test("Local Claude Code data is never modified")
    func localDataIsNeverModified() async throws {
        let fake = try FakeHome()
        defer { fake.remove() }
        let urls = [
            try fake.write(
                [jsonLine("2026-10-15 09:00", session: "s-1", input: 200), Data("not json".utf8)], folder: "alpha"),
            try fake.write([jsonLine("2026-10-14 09:00", session: "s-2", output: 300)], folder: "beta"),
        ]
        let knownDate = Date(timeIntervalSince1970: 1_700_000_000)
        for url in urls {
            try FileManager.default.setAttributes([.modificationDate: knownDate], ofItemAtPath: url.path)
        }
        let before = try urls.map { try Data(contentsOf: $0) }
        let listingBefore = try FileManager.default.subpathsOfDirectory(atPath: fake.projects.path).sorted()

        let source = LocalClaudeProjectsSource(root: fake.projects)
        _ = try await source.scan()
        _ = try await source.scan()

        for (index, url) in urls.enumerated() {
            #expect(try Data(contentsOf: url) == before[index])
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let modified = try #require(attributes[.modificationDate] as? Date)
            #expect(modified == knownDate)
        }
        let listingAfter = try FileManager.default.subpathsOfDirectory(atPath: fake.projects.path).sorted()
        #expect(listingAfter == listingBefore)
    }

    // ---------- Errors / empty / permissions on a real file system ----------

    @Test("No Claude Code data on this Mac")
    func noClaudeCodeDataOnThisMac() async throws {
        let fake = try FakeHome()
        defer { fake.remove() }
        try FileManager.default.removeItem(at: fake.projects)

        await #expect(throws: RefreshFailure.noData) {
            _ = try await LocalClaudeProjectsSource(root: fake.projects).scan()
        }
    }

    @Test("Claude Code data folder exists but holds no files")
    func dataFolderExistsButHoldsNoFiles() async throws {
        let fake = try FakeHome()
        defer { fake.remove() }

        let scan = try await LocalClaudeProjectsSource(root: fake.projects).scan()
        let snapshot = try aggregateScan(scan, now: "2026-10-15 10:00").get()
        #expect(snapshot.totals.total == 0)
        #expect(snapshot.topSessions.isEmpty)
    }

    @Test("No readable usage record at all")
    func noReadableUsageRecordAtAll() async throws {
        let fake = try FakeHome()
        defer { fake.remove() }
        try fake.write([Data("garbage".utf8), Data("{\"foo\": 1}".utf8), Data("[1,2".utf8)], folder: "alpha")

        let scan = try await LocalClaudeProjectsSource(root: fake.projects).scan()
        let result = aggregateScan(scan, now: "2026-10-15 10:00")
        #expect(result == .failure(.unreadableData))
    }

    @Test("Permission denied reading Claude Code data")
    func permissionDeniedReadingClaudeCodeData() async throws {
        try #require(geteuid() != 0, "permission checks are meaningless as root")
        let fake = try FakeHome()
        defer { fake.remove() }
        try fake.write([jsonLine("2026-10-15 09:00", input: 200)], folder: "alpha")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fake.projects.path)

        await #expect(throws: RefreshFailure.permissionDenied) {
            _ = try await LocalClaudeProjectsSource(root: fake.projects).scan()
        }
    }
}
