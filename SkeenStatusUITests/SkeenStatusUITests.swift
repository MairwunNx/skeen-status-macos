import XCTest

final class SkeenStatusUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
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

        XCTAssertTrue(app.menuItems["Проверить сейчас"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Настройки…"].exists)
        XCTAssertTrue(app.menuItems["Выход"].exists)
    }

    @MainActor
    func testOpensSettingsWindowFromMenu() throws {
        let app = launchedApp()
        try statusItem(in: app).click()

        let settings = app.menuItems["Настройки…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()

        let window = app.windows["Skeen Status"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["settings.save"].exists)
        XCTAssertTrue(window.buttons["Проверить связь"].exists)
        XCTAssertTrue(window.staticTexts["Skeen Status"].exists)
    }

    @MainActor
    func testGatewayFieldIsEditable() throws {
        let app = launchedApp()
        try statusItem(in: app).click()
        app.menuItems["Настройки…"].click()

        let window = app.windows["Skeen Status"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let gateway = window.textFields["settings.gateway"]
        XCTAssertTrue(gateway.waitForExistence(timeout: 5))
        gateway.click()
        gateway.typeKey("a", modifierFlags: .command)
        gateway.typeText("10.0.0.1")
        XCTAssertEqual(gateway.value as? String, "10.0.0.1")
    }
}
