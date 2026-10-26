import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var engine: Engine!
    private var statusController: StatusItemController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = ConfigStore.load()
        appState = AppState(config: config)
        engine = Engine(appState: appState)

        statusController = StatusItemController(appState: appState, engine: engine)
        statusController.onOpenSettings = { [weak self] in self?.openSettings() }
        engine.onStateChange = { [weak self] state in self?.statusController.update(state: state) }

        AppLog.shared.log("app launched")
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.shared.log("app terminating")
    }

    private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(appState: appState, engine: engine)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Skeen Status"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 640))
        window.minSize = NSSize(width: 560, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
