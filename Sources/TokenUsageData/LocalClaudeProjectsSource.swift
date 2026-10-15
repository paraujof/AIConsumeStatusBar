import Foundation
import TokenUsageCore

public final class LocalClaudeProjectsSource: UsageSource, @unchecked Sendable {
    private struct Fingerprint: Equatable {
        let size: Int
        let modified: Date?
        let changed: Date?
        let identifier: String
    }

    private let root: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "dev.pablo.AIConsumeStatusBar.file-io", qos: .utility)
    // Only read and written on `queue`.
    private var cache: [String: (Fingerprint, UsageFileDigest)] = [:]

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
        .attributeModificationDateKey, .fileResourceIdentifierKey, .isReadableKey,
    ]

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public func scan() async throws -> UsageScan {
        let token = ScanCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UsageScan, any Error>) in
                queue.async {
                    do {
                        continuation.resume(returning: try self.performScan(token))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            token.cancel()
        }
    }

    private static func isPermissionDenied(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == CocoaError.fileReadNoPermission.rawValue) { return true }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EACCES) || ns.code == Int(EPERM)) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== ns {
            return isPermissionDenied(underlying)
        }
        return false
    }

    private func performScan(_ token: ScanCancellation) throws -> UsageScan {
        if token.isCancelled { throw CancellationError() }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw RefreshFailure.noData
        }
        let projectEntries: [URL]
        do {
            projectEntries = try fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            throw Self.isPermissionDenied(error) ? RefreshFailure.permissionDenied : RefreshFailure.unreadableData
        }

        var digests: [UsageFileDigest] = []
        var denied = 0
        var unreadable = 0
        var livePaths = Set<String>()

        for project in projectEntries.sorted(by: { $0.path < $1.path }) {
            if token.isCancelled { throw CancellationError() }
            guard let pv = try? project.resourceValues(forKeys: Set(Self.keys)),
                pv.isSymbolicLink != true, pv.isDirectory == true
            else { continue }
            let files: [URL]
            do {
                files = try fileManager.contentsOfDirectory(
                    at: project, includingPropertiesForKeys: Self.keys, options: [])
            } catch {
                if Self.isPermissionDenied(error) { denied += 1 } else { unreadable += 1 }
                continue
            }
            for file in files.sorted(by: { $0.path < $1.path }) {
                if token.isCancelled { throw CancellationError() }
                guard file.pathExtension == "jsonl",
                    let fv = try? file.resourceValues(forKeys: Set(Self.keys)),
                    fv.isSymbolicLink != true, fv.isRegularFile == true
                else { continue }
                let path = file.path
                livePaths.insert(path)
                let fingerprint = Fingerprint(
                    size: fv.fileSize ?? -1,
                    modified: fv.contentModificationDate,
                    changed: fv.attributeModificationDate,
                    identifier: fv.fileResourceIdentifier.map { String(describing: $0) } ?? ""
                )
                if let (cachedPrint, digest) = cache[path], cachedPrint == fingerprint {
                    if fv.isReadable == true {
                        digests.append(digest)
                    } else {
                        cache[path] = nil
                        denied += 1
                    }
                    continue
                }
                do {
                    let digest = try readDigest(file, token: token)
                    cache[path] = (fingerprint, digest)
                    digests.append(digest)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    cache[path] = nil
                    if Self.isPermissionDenied(error) { denied += 1 } else { unreadable += 1 }
                }
            }
        }
        for key in cache.keys where !livePaths.contains(key) { cache[key] = nil }
        return UsageScan(files: digests, permissionDeniedFileCount: denied, unreadableFileCount: unreadable)
    }

    private func readDigest(_ file: URL, token: ScanCancellation) throws -> UsageFileDigest {
        var records: [UsageRecord] = []
        var nonEmpty = 0
        var interned: [String: String] = [:]
        func intern(_ s: String?) -> String? {
            guard let s else { return nil }
            if let existing = interned[s] { return existing }
            interned[s] = s
            return s
        }
        try LineReader.forEachLine(in: file, cancellation: token) { line in
            guard line.contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0D }) else { return }
            nonEmpty += 1
            guard let r = UsageRecordParser.parse(line: line) else { return }
            records.append(
                UsageRecord(
                    timestamp: r.timestamp, sessionId: intern(r.sessionId), cwd: intern(r.cwd),
                    responseKey: r.responseKey, tokens: r.tokens))
        }
        return UsageFileDigest(path: file.path, records: records, nonEmptyLineCount: nonEmpty)
    }
}
