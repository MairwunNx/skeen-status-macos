import AppKit
import ComposableArchitecture

/// Owns the NSStatusItem: draws the colored dot and rebuilds the dropdown
/// from the store each time it opens.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: StoreOf<AppFeature>
    private var observation: ObserveToken?

    init(store: StoreOf<AppFeature>) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.setAccessibilityIdentifier("skeen.statusItem")

        observation = observe { [weak self] in
            guard let self else { return }
            let state = self.store.monitor.snapshot.state
            self.statusItem.button?.image = Self.indicatorImage(for: statusColor(for: state))
            self.statusItem.button?.toolTip = "skeen \(state.title)"
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let model = menuModel(
            snapshot: store.monitor.snapshot,
            singBox: store.monitor.singBox,
            gateway: store.monitor.config.gateway
        )

        menu.addItem(header(model.title, color: model.color))
        for line in [model.processLine, model.runtimeLine, model.routeLine].compactMap({ $0 }) {
            menu.addItem(info(line))
        }
        if let error = model.errorLine {
            let item = info(error)
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(info(model.lastCheckLine))
        menu.addItem(info(model.routerLine))

        menu.addItem(.separator())
        if model.canStart {
            menu.addItem(action("Запустить skeen", #selector(startService)))
        }
        menu.addItem(action("Проверить сейчас", #selector(checkNow), key: "r"))
        menu.addItem(action("Лог sing-box…", #selector(openLogs)))
        menu.addItem(action("Настройки…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(action("Выйти", #selector(quit), key: "q"))
    }

    /// The colored dot and the state; a click opens the overview. The dot
    /// is a glyph in the title, since macOS 26 drops custom item images.
    private func header(_ title: String, color: StatusColor) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openOverview), keyEquivalent: "")
        item.target = self
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: "● ", attributes: [.font: font, .foregroundColor: Self.nsColor(for: color)])
        text.append(NSAttributedString(string: title, attributes: [.font: font.bold]))
        item.attributedTitle = text
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func checkNow() { store.send(.monitor(.checkNow)) }
    @objc private func startService() { store.send(.service(.run(.start))) }
    @objc private func openSettings() { store.send(.openSettings(nil)) }
    @objc private func openOverview() { store.send(.openSettings(.overview)) }
    @objc private func openLogs() { store.send(.openSettings(.logs)) }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Indicator drawing

    /// A small lit sphere in the state's color, the still twin of the
    /// animated orb in the window. The menu bar stays still to spare the battery.
    static func indicatorImage(for color: StatusColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let ball = rect.insetBy(dx: 2.5, dy: 2.5)
            let path = NSBezierPath(ovalIn: ball)
            let base = nsColor(for: color)
            let gradient = NSGradient(colors: [base.blended(withFraction: 0.55, of: .white) ?? base, base, base.blended(withFraction: 0.35, of: .black) ?? base])
            gradient?.draw(in: path, relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
            NSColor.black.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 0.75
            path.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "skeen"
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

private extension NSFont {
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
