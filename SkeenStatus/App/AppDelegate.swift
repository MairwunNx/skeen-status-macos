import AppKit
import ComposableArchitecture
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: StoreOf<AppFeature>!
    private var statusController: StatusItemController!
    private var settingsWindow: NSWindow?
    private var observations: [ObserveToken] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the host of unit tests the app stays idle: test dependencies
        // would report every live call as unimplemented.
        guard !isTesting else { return }

        // Shared state loads through dependencies, so the demo must be in
        // place before the state exists, not only inside the store.
        var initialState = withDependencies {
            if DemoMode.isOn { DemoMode.apply(to: &$0) }
        } operation: {
            AppFeature.State()
        }
        if DemoMode.isOn {
            initialState.monitor.history = DemoMode.history(until: Date())
        }
        store = Store(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            if DemoMode.isOn { DemoMode.apply(to: &$0) }
        }
        statusController = StatusItemController(store: store)

        var lastRequest = store.settingsRequest
        observations.append(observe { [weak self] in
            guard let self else { return }
            let request = self.store.settingsRequest
            guard request != lastRequest else { return }
            lastRequest = request
            self.showSettings()
        })

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        store.send(.launched)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count,
           let tab = SettingsTab(rawValue: arguments[index + 1]) {
            store.send(.openSettings(tab))
        } else if arguments.contains("--open-settings") {
            store.send(.openSettings(nil))
        }
    }

    /// Opening the app again from Finder or Spotlight shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store?.send(.openSettings(nil))
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func systemDidWake() {
        store.send(.systemDidWake)
    }

    // MARK: Settings window

    /// The window is built on each open and torn down on close, so the logs
    /// tab stops polling the router the moment it is out of sight.
    private func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingController(rootView: SettingsRootView(store: store))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Skeen Status"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1080, height: 760))
        window.isReleasedWhenClosed = false
        // Never bring the window back on login: the app starts in the menu bar.
        window.isRestorable = false
        window.delegate = self
        // The demo keeps one size so screenshots match from run to run.
        if DemoMode.isOn {
            window.setContentSize(NSSize(width: 1120, height: 1060))
            window.center()
        } else {
            window.setFrameAutosaveName("SkeenStatusSettings")
            if !window.setFrameUsingName("SkeenStatusSettings") {
                window.center()
            }
        }
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == settingsWindow else { return }
        window.contentViewController = nil
        settingsWindow = nil
    }
}
