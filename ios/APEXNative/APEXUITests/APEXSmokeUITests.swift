import XCTest

@MainActor
final class APEXSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFivePortalNavigationAndCoreScreens() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["portal.transition"].exists)
        XCTAssertTrue(app.buttons["portal.main"].exists)
        XCTAssertTrue(scrollUntilVisible(app.buttons["portal.orbit"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.buttons["portal.avatar"], in: app))

        scrollToTop(in: app)

        app.buttons["portal.nutrition"].tap()
        XCTAssertTrue(app.staticTexts["Today's Activities"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Daily targets"].exists)
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Meal timeline"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Supplement stack"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Daily log"], in: app))
        tapBack(in: app)

        XCTAssertTrue(scrollUntilVisible(app.buttons["portal.orbit"], in: app))
        app.buttons["portal.orbit"].tap()
        XCTAssertTrue(app.staticTexts["APEX ORBIT · RUN INTELLIGENCE"].waitForExistence(timeout: 3))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Recent runs"], in: app))
        tapBack(in: app)

        XCTAssertTrue(scrollUntilVisible(app.buttons["portal.avatar"], in: app))
        app.buttons["portal.avatar"].tap()
        XCTAssertTrue(app.staticTexts["Your performance body"].waitForExistence(timeout: 3))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["What your body needs now"], in: app))
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            configuredApp().launch()
        }
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-apex-ui-test", "-AppleLanguages", "(en)"]
        app.launchEnvironment["APEX_UI_TESTING"] = "1"
        return app
    }

    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 10) -> Bool {
        if element.exists && element.isHittable { return true }
        for _ in 0..<attempts {
            app.swipeUp()
            if element.exists && element.isHittable { return true }
        }
        return element.exists
    }

    private func scrollToTop(in app: XCUIApplication) {
        for _ in 0..<8 { app.swipeDown() }
    }

    private func tapBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 2))
        back.tap()
    }
}
