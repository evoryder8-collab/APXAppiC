import XCTest

@MainActor
final class APEXSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInductionOffersSkipAndNoPlanAccountCanReturnToTheBuilder() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-apex-preview", "induction", "-apex-ui-test-first-run", "-AppleLanguages", "(en)",
        ]
        app.launchEnvironment["APEX_UI_TESTING"] = "1"
        app.launch()

        let skip = app.buttons["induction-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 4))
        XCTAssertTrue(skip.isHittable)
        skip.tap()

        let finishConsent = app.buttons["consent-finish"]
        XCTAssertTrue(finishConsent.waitForExistence(timeout: 4), "skip must advance to consent")
        finishConsent.tap()

        let transition = app.buttons["portal.transition"]
        XCTAssertTrue(transition.waitForExistence(timeout: 4))
        XCTAssertTrue(scrollUntilVisible(transition, in: app, attempts: 4))
        tapClearOfDock(transition)
        XCTAssertTrue(
            app.buttons["induction-open"].waitForExistence(timeout: 4),
            "the same skipped account needs a route back with no generated rows"
        )
        XCTAssertTrue(app.staticTexts["training-no-plan"].exists)
        XCTAssertFalse(app.staticTexts["Rest day"].exists)
        XCTAssertFalse(
            app.staticTexts["TODAY'S SIGNAL"].exists,
            "a skipped induction must not fabricate a muscle signal"
        )
        XCTAssertFalse(app.descendants(matching: .any)["training-muscle-signal"].exists)

        app.buttons["induction-open"].tap()
        let allElements = app.descendants(matching: .any)
        let goal = allElements["induction-return-goal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 4))
        XCTAssertTrue(allElements["induction-return-venue"].exists)
        XCTAssertTrue(allElements["induction-return-sessions"].exists)

        goal.tap()
        let strength = allElements["induction-return-goal-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 2))
        strength.tap()
        allElements["induction-return-venue-outdoors"].tap()
        allElements["induction-return-sessions-5"].tap()

        let equipment = allElements["induction-return-equipment-adjustable_dumbbells"]
        XCTAssertTrue(
            scrollUntilVisible(
                equipment,
                in: app,
                attempts: 12
            )
        )
        equipment.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(equipment.value as? String, "1")
        let pain = allElements["induction-return-pain-knee"]
        XCTAssertTrue(
            scrollUntilVisible(pain, in: app, attempts: 12)
        )
        pain.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(pain.value as? String, "1")

        app.buttons["induction-install"].tap()
        XCTAssertFalse(
            app.buttons["induction-open"].waitForExistence(timeout: 5),
            "a complete saved plan must close the return route"
        )
        let installedState = app.staticTexts["induction-installed-state"]
        XCTAssertTrue(
            installedState.waitForExistence(timeout: 3),
            "the UI-selected answers must reach plan metadata and rows"
        )
        XCTAssertEqual(
            installedState.value as? String,
            "goal=strength;venue=outdoors;sessions=3;equipment=adjustable_dumbbells;pain=knee;transitionRows=3;mainRows=3"
        )
    }

    func testIncompleteGeneratedPlanCannotExposeARunnableDay() {
        let app = configuredApp()
        app.launchArguments.append("-apex-ui-test-incomplete-plan")
        app.launch()

        let transition = app.buttons["portal.transition"]
        XCTAssertTrue(transition.waitForExistence(timeout: 4))
        XCTAssertTrue(scrollUntilVisible(transition, in: app, attempts: 4))
        tapClearOfDock(transition)

        XCTAssertTrue(app.staticTexts["training-no-plan"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["training-today-open"].exists)
        XCTAssertFalse(app.otherElements["training-calendar"].exists)
        XCTAssertFalse(app.staticTexts["TODAY'S SIGNAL"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["training-muscle-signal"].exists)
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
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["GOAL"].exists)
        XCTAssertTrue(app.staticTexts["ACTIVITY LEVEL"].exists)
        capture("nutrition-target-sheet")
        app.buttons["Close"].tap()

        /* Asserted in the order the screen lays them out, because the helper
           only ever scrolls downward. The detail lives inside collapsed
           sections now, so each one is opened before it is inspected. */
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Meals and training"], in: app))
        capture("nutrition-dayline")
        XCTAssertTrue(expandSection("activities", revealing: app.staticTexts["Today's Activities"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Today's Activities"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Daily targets"], in: app))
        XCTAssertTrue(expandSection("meal-timeline", revealing: app.staticTexts["Meal timeline"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Meal timeline"], in: app))
        XCTAssertTrue(expandSection("supplements", revealing: app.staticTexts["Supplement stack"], in: app))
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
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Upper Body Strength"].firstMatch, in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Lower Body Strength"].firstMatch, in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["What your body needs"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["How are your joints this week?"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["APEX ASSESSMENT"], in: app))
        capture("avatar-joint-check-in")
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Cardio & recovery evidence"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["How regularly you eat"], in: app))
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            configuredApp().launch()
        }
    }

    func testTrainingCalendarShowsPrescriptionAndHonestEmptyDay() {
        let app = configuredApp()
        app.launch()

        let main = app.buttons["portal.main"]
        XCTAssertTrue(scrollUntilVisible(main, in: app))
        main.tap()

        let today = calendarKey(offset: 0)
        let tomorrow = calendarKey(offset: 1)
        let todayCell = app.buttons["calendar-day-\(today)"]
        XCTAssertTrue(scrollUntilVisible(todayCell, in: app))
        XCTAssertTrue(todayCell.label.contains("Scheduled"), todayCell.label)

        let emptyCell = app.buttons["calendar-day-\(tomorrow)"]
        XCTAssertTrue(emptyCell.exists)
        XCTAssertTrue(emptyCell.label.contains("No prescription"), emptyCell.label)
        capture("training-calendar-states")
        emptyCell.tap()

        XCTAssertTrue(app.staticTexts["No workout prescribed"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No programme was authored for this date."].exists)
        XCTAssertFalse(app.staticTexts["Rest day"].exists)
        capture("training-calendar-no-prescription")
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
        /* Overlapping Dayline cards used to hand the tap to a neighbouring
           meal, which then failed further down for the wrong reason. */
        XCTAssertTrue(app.staticTexts["ACTUAL INTAKE · BREAKFAST"].exists, "tapped breakfast, opened something else")
        /* The presets card sits below the fold inside a lazy stack, so it is not
           built until the sheet is scrolled to it. */
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["FAST STARTS"], in: app))
        XCTAssertTrue(app.buttons["Select"].firstMatch.waitForExistence(timeout: 3))
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
        /* The count label lands a frame after the button enables. */
        XCTAssertTrue(app.descendants(matching: .any)["meal-selection-count"].waitForExistence(timeout: 3))
        capture("meal-composer-selection")
    }

    func testWorkoutPlayerGuidesAndRecordsActualSet() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.transition"].waitForExistence(timeout: 4))
        app.buttons["portal.transition"].tap()

        /* The day card, not the today hero, which repeats the same title. */
        let trainingDay = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "training-day-")
        ).firstMatch
        XCTAssertTrue(scrollUntilVisible(trainingDay, in: app))
        /* A card in the middle of the list is nowhere near the dock, so let
           XCUITest scroll it in and hit its centre. */
        trainingDay.tap()

        let start = app.buttons["workout-start-session"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "the day view should have pushed")
        XCTAssertTrue(scrollUntilVisible(start, in: app))
        app.swipeUp()
        tapClearOfDock(start)

        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-warmup"].waitForExistence(timeout: 10))
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
        let reps = app.textFields["exercise-fact-reps"]
        XCTAssertTrue(reps.waitForExistence(timeout: 2))
        reps.tap()
        reps.typeText("8")
        XCTAssertTrue(app.buttons["+30s"].exists)
        capture("workout-rest")
        XCTAssertTrue(app.buttons["workout-skip-rest"].isEnabled)
        app.buttons["workout-skip-rest"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-active"].waitForExistence(timeout: 2))
    }

    /// A finished session used to save and vanish. The receipt is the only
    /// place the load reported during the workout is handed back.
    func testFinishingAWorkoutShowsTheReceipt() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.transition"].waitForExistence(timeout: 4))
        app.buttons["portal.transition"].tap()

        let trainingDay = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "training-day-")
        ).firstMatch
        XCTAssertTrue(scrollUntilVisible(trainingDay, in: app))
        trainingDay.tap()

        let start = app.buttons["workout-start-session"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilVisible(start, in: app))
        app.swipeUp()
        tapClearOfDock(start)

        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-warmup"].waitForExistence(timeout: 10))
        app.buttons["workout-skip-warmup"].tap()

        /* Work through every set the plan holds, however many that is, rather
           than hard-coding a count that a plan change would silently break. */
        var guardRail = 0
        while guardRail < 40 {
            guardRail += 1
            if app.descendants(matching: .any)["workout-phase-complete"].exists { break }
            if app.buttons["workout-finish-set-review"].exists {
                app.buttons["workout-finish-set-review"].tap()
                continue
            }
            if app.buttons["workout-skip-active-set"].exists {
                app.buttons["workout-skip-active-set"].tap()
                continue
            }
            if app.buttons["workout-skip-rest"].exists {
                app.buttons["workout-skip-rest"].tap()
                continue
            }
            break
        }

        let complete = app.descendants(matching: .any)["workout-phase-complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 6), "the player should reach its complete phase")
        capture("workout-complete")

        let save = app.buttons["Save workout"]
        XCTAssertTrue(scrollUntilVisible(save, in: app))
        tapClearOfDock(save)

        let done = app.buttons["workout-receipt-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the receipt should appear after saving")
        XCTAssertTrue(app.staticTexts["Stats at a glance"].exists, "the receipt should be titled")
        capture("workout-receipt")
        done.tap()
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-apex-ui-test", "-AppleLanguages", "(en)"]
        app.launchEnvironment["APEX_UI_TESTING"] = "1"
        return app
    }

    private func calendarKey(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Opens a collapsible section and leaves it open, waiting for the thing it
    /// reveals so the assertions that follow do not race the animation.
    @discardableResult
    private func expandSection(
        _ id: String,
        revealing reveal: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        let toggle = app.buttons["section-toggle-\(id)"]
        guard scrollUntilVisible(toggle, in: app), isReachable(toggle) else { return false }
        /* The open/closed state persists between launches, so never blind-tap:
           that would close a section a previous run left open. */
        if toggle.value as? String == "Expanded" { return true }
        tapClearOfDock(toggle)
        return reveal.firstMatch.waitForExistence(timeout: 4)
    }

    /*
     * Asking XCUITest about an element off the screen raises rather than
     * answering, and so does asking about a query that matches more than one
     * element. Resolve to a single match and check it has a real frame before
     * asking anything else.
     */
    private func isReachable(_ element: XCUIElement) -> Bool {
        let target = element.firstMatch
        guard target.exists else { return false }
        let frame = target.frame
        guard frame.width > 0, frame.height > 0 else { return false }
        return target.isHittable
    }

    /*
     * A centred flick lands on whatever card happens to be mid-screen, and a
     * card that runs its own gestures gives up less of the scroll. Alternate a
     * plain flick with a drag along the left gutter, which on every screen is
     * label space rather than anything interactive.
     */
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 60) -> Bool {
        if isReachable(element) { return true }
        for attempt in 0..<attempts {
            if attempt.isMultiple(of: 2) {
                app.swipeUp()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.78))
                    .press(
                        forDuration: 0.02,
                        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.28))
                    )
            }
            if isReachable(element) { return true }
        }
        return element.firstMatch.exists
    }

    /// The profile dock floats over the bottom of every screen and takes any
    /// tap that lands on it, so tap a control through its own upper half.
    /// A flick keeps travelling after the swipe ends, so a tap issued straight
    /// away lands wherever the content has drifted to. Wait for the frame to
    /// stop moving, then aim at the control's upper half to clear the dock.
    private func tapClearOfDock(_ element: XCUIElement) {
        let target = element.firstMatch
        var previous = target.exists ? target.frame : .zero
        for _ in 0..<10 {
            let expectation = XCTestExpectation(description: "settle")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
            _ = XCTWaiter().wait(for: [expectation], timeout: 1)
            guard target.exists else { break }
            let current = target.frame
            if current == previous { break }
            previous = current
        }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
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
