import XCTest

/// Drives the app in `--demo` mode: a made-up router, no network, no Keychain.
final class SkeenStatusUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchedApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-AppleLanguages", "(en)"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func statusItem(in app: XCUIApplication) throws -> XCUIElement {
        let item = app.statusItems["skeen.statusItem"]
        guard item.waitForExistence(timeout: 10) else {
            throw XCTSkip("Status item is not reachable in this UI-test environment.")
        }
        return item
    }

    @MainActor
    func testStatusItemMenuShowsActions() throws {
        let app = launchedApp()
        try statusItem(in: app).click()

        XCTAssertTrue(app.menuItems["Check Now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Settings…"].exists)
        XCTAssertTrue(app.menuItems["Quit"].exists)
    }

    @MainActor
    func testOpensSettingsWindowFromMenu() throws {
        let app = launchedApp()
        try statusItem(in: app).click()

        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["overview.checkNow"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditingTheGatewayOffersToSave() throws {
        let app = launchedApp(["--open-settings"])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        window.outlines.staticTexts["Connection"].click()
        let gateway = window.textFields["settings.gateway"]
        XCTAssertTrue(gateway.waitForExistence(timeout: 5))
        gateway.click()
        gateway.typeKey("a", modifierFlags: .command)
        gateway.typeText("10.0.0.1")
        XCTAssertEqual(gateway.value as? String, "10.0.0.1")
        XCTAssertTrue(window.buttons["settings.save"].waitForExistence(timeout: 5))
    }
}
