import os

/// Lock-backed cancellation flag bridged from Swift task cancellation to the I/O queue.
final class ScanCancellation: Sendable {
    private let flag = OSAllocatedUnfairLock<Bool>(initialState: false)

    var isCancelled: Bool { flag.withLock { $0 } }

    func cancel() {
        flag.withLock { $0 = true }
    }
}
