import AppKit

/// Owns the NSStatusItem: draws the colored indicator and builds the dropdown
/// menu on demand from the shared AppState.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let engine: Engine

    var onOpenSettings: (() -> Void)?

    init(appState: AppState, engine: Engine) {
        self.appState = appState
        self.engine = engine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.setAccessibilityIdentifier("skeen.statusItem")
        update(state: appState.status)
    }

    func update(state: SkeenState) {
        statusItem.button?.image = Self.indicatorImage(for: statusColor(for: state))
        statusItem.button?.toolTip = "Skeen: \(state.keyword)"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let model = menuModel(
            state: appState.status,
            lastCheck: appState.lastCheck,
            gateway: appState.config.gateway,
            now: Date()
        )

        menu.addItem(header(model.title, color: statusColor(for: appState.status)))
        menu.addItem(.separator())
        menu.addItem(disabled(model.statusDetail))
        if let memory = model.memoryLine {
            menu.addItem(disabled(memory))
        }
        menu.addItem(disabled(model.lastCheckLine))
        menu.addItem(disabled(model.routerLine))
        menu.addItem(.separator())

        menu.addItem(action("Проверить сейчас", #selector(checkNow)))
        menu.addItem(action("Настройки…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(action("Выход", #selector(quit)))
    }

    private func header(_ title: String, color: StatusColor) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = Self.indicatorImage(for: color)
        item.isEnabled = false
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func checkNow() { engine.checkNow() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Indicator drawing

    static func indicatorImage(for color: StatusColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(ovalIn: inset)
            nsColor(for: color).setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func nsColor(for color: StatusColor) -> NSColor {
        switch color {
        case .green: return .systemGreen
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .gray: return .systemGray
        }
    }
}
