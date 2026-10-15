import AppKit
import TokenUsageCore
import TokenUsageData
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: RefreshCoordinator?
    private var controller: StatusBarController?
    private var wakeObserver: WakeObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        let source = LocalClaudeProjectsSource(root: root)
        let now: @Sendable () -> Date = { Date() }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // The controller does not exist yet when the coordinator is built; bridge through a box.
        let box = ControllerBox()
        let logger = Logger(subsystem: "dev.pablo.AIConsumeStatusBar", category: "refresh")
        let coordinator = RefreshCoordinator(
            source: source, sleeper: TaskSleeper(), now: now, calendar: calendar,
            log: { event in
                switch event {
                case .skippedInProgress: logger.info("skipped: refresh in progress")
                case .lateResultDiscarded: logger.info("late result discarded")
                case .failed(let reason): logger.error("refresh failed: \(reason, privacy: .public)")
                }
            },
            onStateChange: { _ in box.controller?.stateDidChange() })
        let controller = StatusBarController(coordinator: coordinator, now: now, calendar: calendar)
        box.controller = controller
        self.coordinator = coordinator
        self.controller = controller
        wakeObserver = WakeObserver { coordinator.refresh() }
        coordinator.startAutomaticRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeObserver?.stop()
        coordinator?.stop()
    }
}

@MainActor
private final class ControllerBox {
    var controller: StatusBarController?
}
