import AppKit
import TokenUsageCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let coordinator: RefreshCoordinator
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let statusItem: NSStatusItem

    init(coordinator: RefreshCoordinator, now: @escaping @Sendable () -> Date, calendar: Calendar) {
        self.coordinator = coordinator
        self.now = now
        self.calendar = calendar
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        apply(render())
    }

    private func render() -> MenuModel {
        MenuPresenter.render(coordinator.state, now: now(), calendar: calendar)
    }

    func apply(_ model: MenuModel) {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: model.iconSymbolName, accessibilityDescription: "Claude Code token usage")
        image?.isTemplate = model.iconIsTemplate
        button.image = image
        button.imagePosition = .imageLeading
        button.title = model.title
    }

    func stateDidChange() {
        apply(render())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let model = render()
        apply(model)
        menu.removeAllItems()
        for line in model.lines {
            switch line {
            case .separator:
                menu.addItem(.separator())
            case .info(let text), .header(let text):
                let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                item.isEnabled = true
                menu.addItem(item)
            case .action(let text, let action):
                let item = NSMenuItem(title: text, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self
                item.isEnabled = true
                item.representedObject = action == .refreshNow ? "refresh" : "quit"
                menu.addItem(item)
            }
        }
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "refresh": coordinator.refresh()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
}
