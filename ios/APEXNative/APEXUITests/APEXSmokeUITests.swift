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
        XCTAssertTrue(app.otherElements["nutrition-glance-card"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Nutrition at a glance"].exists)

        let targetButton = app.buttons["Nutrition at a glance"]
        XCTAssertTrue(targetButton.exists)
        targetButton.tap()
        XCTAssertTrue(app.navigationBars["Daily calorie target"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["GOAL"].exists)
        XCTAssertTrue(app.staticTexts["ACTIVITY LEVEL"].exists)
        capture("nutrition-target-sheet")
        app.buttons["Done"].tap()

        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Today's Activities"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Daily targets"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Meals and training"], in: app))
        capture("nutrition-dayline")
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
        XCTAssertTrue(app.staticTexts["Avatar"].waitForExistence(timeout: 3))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["APEX BODY INDEX"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Your performance body"], in: app))
        capture("avatar-body-index")
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Metabolic rhythm"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Cardio & recovery evidence"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["What your body needs"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Upper Body Strength"].firstMatch, in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Lower Body Strength"].firstMatch, in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["APEX ASSESSMENT"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["How are your joints this week?"], in: app))
        capture("avatar-joint-check-in")
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            configuredApp().launch()
        }
    }

    func testMealComposerPreservesFoodMemoryAndPresetWorkflow() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        app.buttons["portal.nutrition"].tap()

        let breakfast = app.staticTexts["meal-dayline-title-breakfast"]
        XCTAssertTrue(scrollUntilVisible(breakfast, in: app))
        breakfast.tap()

        XCTAssertTrue(app.staticTexts["Build this meal"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["FAST STARTS"].exists)
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 3))
        capture("meal-composer-compact")

        let displayControl = app.segmentedControls.firstMatch
        XCTAssertTrue(displayControl.waitForExistence(timeout: 2))
        displayControl.buttons["Expanded"].tap()
        XCTAssertTrue(app.switches["Adaptive"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Lock"].exists)
        capture("meal-composer-expanded")

        app.buttons["Select"].tap()
        let firstFood = app.buttons["meal-item-select-Swiss rolled oats"]
        XCTAssertTrue(firstFood.waitForExistence(timeout: 2))
        firstFood.tap()
        XCTAssertTrue(app.buttons["Create preset"].isEnabled)
        XCTAssertTrue(app.staticTexts["1 selected"].exists)
        capture("meal-composer-selection")
    }

    func testWorkoutPlayerGuidesAndRecordsActualSet() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.transition"].waitForExistence(timeout: 4))
        app.buttons["portal.transition"].tap()

        let trainingDay = app.staticTexts["Full-body foundation"]
        XCTAssertTrue(scrollUntilVisible(trainingDay, in: app))
        trainingDay.tap()

        let start = app.buttons["workout-start-session"]
        XCTAssertTrue(scrollUntilVisible(start, in: app))
        start.tap()

        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-warmup"].waitForExistence(timeout: 3))
        capture("workout-warmup")
        app.buttons["workout-skip-warmup"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-active"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Push-ups"].exists)
        /* Reps count themselves now (tempo cadence). The athlete only
           pauses, finishes, or skips. */
        XCTAssertTrue(app.buttons["workout-pause-set"].exists)
        XCTAssertFalse(app.buttons["workout-count-rep"].exists)
        app.buttons["workout-end-set"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-rest"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Actual reps"].exists)
        XCTAssertTrue(app.staticTexts["Weight used"].exists)
        XCTAssertTrue(app.buttons["+30s"].exists)
        capture("workout-rest")
        app.buttons["workout-skip-rest"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-active"].waitForExistence(timeout: 2))
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
