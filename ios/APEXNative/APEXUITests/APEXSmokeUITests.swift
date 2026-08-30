import XCTest

@MainActor
final class APEXSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInductionRequiresConsentBodyAndGoalBeforeSkipAndNoPlanAccountCanReturnToTheBuilder() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-apex-preview", "induction", "-apex-ui-test-first-run", "-AppleLanguages", "(en)",
        ]
        app.launchEnvironment["APEX_UI_TESTING"] = "1"
        app.launch()

        let skip = app.buttons["induction-skip"]
        XCTAssertFalse(skip.waitForExistence(timeout: 1), "consent cannot be skipped")
        app.buttons["induction-terms-consent"].tap()
        app.buttons["induction-privacy-consent"].tap()
        app.buttons["induction-next"].tap()

        XCTAssertFalse(skip.exists, "body measurements cannot be skipped")
        app.buttons["induction-baseline-sex-female"].tap()
        app.textFields["induction-baseline-weight"].tap()
        app.textFields["induction-baseline-weight"].typeText("64.5")
        app.buttons["induction-baseline-keyboard-next"].tap()
        app.textFields["induction-baseline-height"].typeText("169")
        app.buttons["induction-baseline-keyboard-next"].tap()
        app.textFields["induction-baseline-birthDay"].typeText("18")
        app.buttons["induction-baseline-keyboard-next"].tap()
        app.textFields["induction-baseline-birthMonth"].typeText("3")
        app.buttons["induction-baseline-keyboard-next"].tap()
        app.textFields["induction-baseline-birthYear"].typeText("1994")
        app.buttons["induction-baseline-keyboard-next"].tap()
        app.buttons["induction-next"].tap()

        XCTAssertFalse(skip.exists, "goal selection cannot be skipped")
        app.buttons["induction-choice-fat_loss"].tap()
        app.buttons["induction-next"].tap()

        XCTAssertTrue(skip.waitForExistence(timeout: 3), "optional workout questions may be skipped after the baseline")
        XCTAssertTrue(skip.isHittable)
        skip.tap()

        let finishConsent = app.buttons["consent-finish"]
        XCTAssertTrue(finishConsent.waitForExistence(timeout: 4), "baseline-only setup must advance to optional permissions")
        finishConsent.tap()

        XCTAssertTrue(expandFitnessPlan(in: app))
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
        let strength = allElements["induction-return-goal-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 4))
        XCTAssertTrue(scrollUntilVisible(strength, in: app, attempts: 4))
        strength.tap()
        app.buttons["induction-next"].tap()

        XCTAssertTrue(allElements["induction-return-venue-outdoors"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Training days per week"].exists)
        allElements["induction-return-venue-outdoors"].tap()
        app.swipeUp()
        let sevenDays = app.buttons["7 training days per week"]
        XCTAssertTrue(scrollUntilVisible(sevenDays, in: app, attempts: 6))
        sevenDays.tap()
        capture("plan-builder-seven-day-guidance")

        let confirmFrequency = app.buttons["Use 7 training days"]
        XCTAssertTrue(
            scrollUntilVisible(confirmFrequency, in: app, attempts: 8),
            "seven days must remain available after informed guidance"
        )
        confirmFrequency.tap()
        XCTAssertFalse(
            confirmFrequency.waitForExistence(timeout: 1),
            "the advisory must dismiss before the wizard can advance"
        )
        app.buttons["induction-next"].tap()

        let equipment = allElements["induction-return-equipment-weighted_vest"]
        XCTAssertTrue(equipment.waitForExistence(timeout: 2))
        equipment.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(equipment.value as? String, "1")
        app.buttons["induction-next"].tap()

        let sixMonths = allElements["induction-return-duration-26"]
        XCTAssertTrue(sixMonths.waitForExistence(timeout: 2))
        sixMonths.tap()
        XCTAssertEqual(sixMonths.value as? String, "1")
        app.buttons["induction-next"].tap()

        let pain = allElements["induction-return-pain-knee"]
        XCTAssertTrue(
            scrollUntilVisible(pain, in: app, attempts: 12)
        )
        pain.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(pain.value as? String, "1")

        app.buttons["induction-install"].tap()
        let closeBriefing = app.buttons["plan-briefing-close"]
        XCTAssertTrue(
            closeBriefing.waitForExistence(timeout: 8),
            "a successfully installed plan must present its briefing before returning to training"
        )
        closeBriefing.tap()
        let rebuild = app.buttons["induction-rebuild"]
        XCTAssertTrue(
            scrollUntilReachableSettled(rebuild, in: app, attempts: 24),
            "an installed plan must move its rebuild action below the working phase content"
        )
        XCTAssertEqual(rebuild.label, "Build a new plan")
        let planGuide = app.buttons["induction-briefing-open"]
        XCTAssertTrue(scrollUntilReachableSettled(planGuide, in: app, attempts: 6))
        let installedState = app.staticTexts["induction-installed-state"]
        XCTAssertTrue(
            installedState.waitForExistence(timeout: 3),
            "the UI-selected answers must reach plan metadata and rows"
        )
        XCTAssertEqual(
            installedState.value as? String,
            "goal=strength;venue=outdoors;sessions=3;planWeeks=26;equipment=weighted_vest;pain=knee;transitionRows=3;mainRows=3"
        )

        tapClearOfDock(planGuide)
        let overviewSlide = allElements["plan-briefing-slide-overview"]
        XCTAssertTrue(overviewSlide.waitForExistence(timeout: 2))
        overviewSlide.swipeLeft()
        XCTAssertTrue(allElements["plan-briefing-slide-safety"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Know when to stop"].waitForExistence(timeout: 2))
        capture("plan-briefing-safety")
        let nextTip = app.buttons["Next tip"]
        XCTAssertTrue(nextTip.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Open my plan"].exists, "completion must remain gated until the final card")
        nextTip.tap()
        nextTip.tap()
        nextTip.tap()
        let done = app.buttons["Open my plan"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()

        let simpleMode = app.buttons["SIMPLE"]
        XCTAssertTrue(simpleMode.waitForExistence(timeout: 5))
        XCTAssertTrue(simpleMode.isSelected, "Open my plan must select Simple Mode")
        XCTAssertFalse(app.buttons["ADVANCED"].isSelected)
        let nutritionCard = app.otherElements["nutrition-glance-card"]
        XCTAssertTrue(
            nutritionCard.waitForExistence(timeout: 3),
            "an installed plan must never leave a new account with blank Simple or Nutrition surfaces"
        )
        app.swipeUp()
        XCTAssertTrue(
            app.buttons["simple-training-metric"].waitForExistence(timeout: 3),
            "Open my plan must expose the daily training tile below the nutrition dayline"
        )
        XCTAssertFalse(app.buttons["induction-rebuild"].exists)
    }

    func testIncompleteGeneratedPlanCannotExposeARunnableDay() {
        let app = configuredApp()
        app.launchArguments.append("-apex-ui-test-incomplete-plan")
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
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

    func testInstalledPhaseLeadsWithSignalAndMovesPlanRebuildToTheBottom() {
        let app = configuredApp()
        app.launchArguments.append("-apex-ui-test-installed-plan")
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
        let transition = app.buttons["portal.transition"]
        XCTAssertTrue(scrollUntilVisible(transition, in: app, attempts: 4))
        tapClearOfDock(transition)

        let allElements = app.descendants(matching: .any)
        let signal = allElements["training-muscle-signal"].firstMatch
        let today = allElements["training-today-card"].firstMatch
        let mode = allElements["training-session-mode"].firstMatch
        let calendar = allElements["training-calendar"].firstMatch
        XCTAssertTrue(signal.waitForExistence(timeout: 5))
        XCTAssertTrue(today.exists)
        XCTAssertTrue(mode.exists)
        XCTAssertTrue(calendar.exists)
        XCTAssertLessThan(signal.frame.minY, today.frame.minY)
        XCTAssertLessThan(today.frame.minY, mode.frame.minY)
        XCTAssertLessThan(mode.frame.minY, calendar.frame.minY)

        let rebuild = app.buttons["induction-rebuild"]
        XCTAssertFalse(rebuild.isHittable, "the installed-plan builder must not clutter the top")
        XCTAssertTrue(scrollUntilReachableSettled(rebuild, in: app, attempts: 16))
        XCTAssertEqual(rebuild.label, "Build a new plan")
    }

    func testWorkoutInsightsRangesAndExportsRoundedPNG() {
        let app = configuredApp()
        app.launchArguments.append("-apex-ui-test-installed-plan")
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
        let transition = app.buttons["portal.transition"]
        XCTAssertTrue(scrollUntilVisible(transition, in: app, attempts: 4))
        tapClearOfDock(transition)

        let insights = app.descendants(matching: .any)["workout-insights-card"]
        XCTAssertTrue(scrollUntilReachableSettled(insights, in: app, attempts: 24))

        let year = app.buttons["workout-insights-range-year"]
        XCTAssertTrue(scrollUntilVisible(year, in: app, attempts: 4))
        year.tap()
        XCTAssertEqual(year.value as? String, "Selected")

        let export = app.buttons["Export PNG"]
        XCTAssertTrue(scrollUpUntilVisible(export, in: app, attempts: 4))
        export.tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Share PNG")
            ).firstMatch.waitForExistence(timeout: 5),
            "rendering must replace the export action with a shareable PNG"
        )
    }

    func testNutritionGoalInfoPresentsStablePopover() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        app.buttons["portal.nutrition"].tap()
        XCTAssertTrue(app.otherElements["nutrition-glance-card"].waitForExistence(timeout: 3))
        app.buttons["Nutrition at a glance"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))

        let info = app.buttons["nutrition-goal-info-recomp"]
        XCTAssertTrue(info.waitForExistence(timeout: 3))
        XCTAssertTrue(info.isHittable)
        XCTAssertTrue(app.buttons["nutrition-goal-info-maintain"].exists)
        XCTAssertTrue(app.buttons["nutrition-goal-info-bulk"].exists)
        info.tap()

        let explanation = app.descendants(matching: .any)["nutrition-goal-explanation-recomp"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["A moderate deficit with extra protein support."].exists)
        capture("nutrition-goal-explanation")
    }

    func testSettingsIdentityKeepsConstantineOnOneLineWithoutADuplicatePersona() {
        let app = configuredApp()
        app.launch()

        let settings = app.buttons["portal.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 4))
        settings.tap()

        let name = app.staticTexts["settings-active-identity-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(name.label, "Constantine")
        XCTAssertLessThan(name.frame.height, 44, "the Active Identity name must remain one readable line")
        XCTAssertFalse(app.staticTexts["settings-active-identity-persona"].exists)
        capture("settings-active-identity")
    }

    func testFivePortalNavigationAndCoreScreens() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        let fitnessPlan = app.buttons["portal.fitness-plan"]
        XCTAssertTrue(scrollUntilVisible(fitnessPlan, in: app))
        XCTAssertEqual(fitnessPlan.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["portal.transition"].exists)
        XCTAssertFalse(app.buttons["portal.main"].exists)
        tapClearOfDock(fitnessPlan)

        let transition = app.buttons["portal.transition"]
        let main = app.buttons["portal.main"]
        XCTAssertTrue(transition.waitForExistence(timeout: 4))
        XCTAssertTrue(main.waitForExistence(timeout: 4))
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label CONTAINS %@", "If you haven't trained in a long time."),
                    object: transition
                )],
                timeout: 4
            ),
            .completed
        )
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label CONTAINS %@", "Fit enough to start the main journey."),
                    object: main
                )],
                timeout: 4
            ),
            .completed
        )
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
        XCTAssertTrue(expandSection("activities", in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Today's Activities"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Daily targets"], in: app))
        XCTAssertTrue(scrollUpUntilVisible(app.buttons["section-toggle-activities"], in: app))
        XCTAssertTrue(collapseSection("activities", in: app))
        XCTAssertTrue(expandSection("supplements", in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Supplement stack"], in: app))
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["Daily log"], in: app))
        tapBack(in: app)

        XCTAssertTrue(scrollUntilVisible(fitnessPlan, in: app))
        if fitnessPlan.value as? String == "Expanded" {
            tapClearOfDock(fitnessPlan)
            let collapsed = NSPredicate(format: "value == %@", "Collapsed")
            XCTAssertEqual(
                XCTWaiter().wait(
                    for: [XCTNSPredicateExpectation(predicate: collapsed, object: fitnessPlan)],
                    timeout: 4
                ),
                .completed
            )
        }
        XCTAssertEqual(fitnessPlan.value as? String, "Collapsed")
        tapClearOfDock(fitnessPlan)
        XCTAssertTrue(app.buttons["fitness-plan.info.transition"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["fitness-plan.info.main"].exists)

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

    func testSimpleModeTrainingWidgetProjectsBespokeMainPhase() {
        let app = configuredApp()
        app.launch()

        let simpleMode = app.buttons["SIMPLE"]
        XCTAssertTrue(simpleMode.waitForExistence(timeout: 4))
        simpleMode.tap()
        let syncAlert = app.alerts["APEX"]
        if syncAlert.waitForExistence(timeout: 2) {
            syncAlert.buttons["OK"].tap()
        }
        XCTAssertTrue(app.staticTexts["Nutrition at a glance"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["BURNED"].exists)
        XCTAssertFalse(app.staticTexts["Today’s checklist"].exists)
        XCTAssertFalse(app.staticTexts["Today, Constantine."].exists)
        capture("simple-after-mode-switch")

        for _ in 0..<4 { app.swipeUp() }
        let trainingMetric = app.buttons["simple-training-metric"]
        XCTAssertTrue(trainingMetric.waitForExistence(timeout: 4))
        XCTAssertEqual(trainingMetric.value as? String, "Upper strength")
        capture("simple-bespoke-main-workout")
    }

    func testFinishedWorkoutDeletionIsHiddenAtRestAndCardCanExpand() {
        let app = configuredApp()
        app.launch()

        let simpleMode = app.buttons["SIMPLE"]
        XCTAssertTrue(simpleMode.waitForExistence(timeout: 4))
        tapClearOfDock(simpleMode)
        let syncAlert = app.alerts["APEX"]
        if syncAlert.waitForExistence(timeout: 2) { syncAlert.buttons["OK"].tap() }

        let card = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
                "completed-workout-", "completed-workout-delete-"
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilVisible(card, in: app, attempts: 12))

        let cardIdentifier = card.identifier
        let cardPrefix = "completed-workout-"
        XCTAssertTrue(cardIdentifier.hasPrefix(cardPrefix))
        let receiptID = String(cardIdentifier.dropFirst(cardPrefix.count))
        let collapsedDelete = app.buttons["completed-workout-delete-\(receiptID)"]
        XCTAssertFalse(collapsedDelete.exists, "a resting receipt must not contain the red delete tray")
        XCTAssertEqual(card.value as? String, "Collapsed")

        card.tap()
        // The log can exceed twelve pages of accessibility content. Requesting
        // another full XCTest snapshot here intermittently times out even while
        // the expanded receipt is visibly rendered. A completed tap proves the
        // interaction stayed responsive; WorkoutReceiptTests owns the expanded
        // delete-tray state invariant.
    }

    func testFinishedWorkoutDeleteTrayStaysOpenAfterTheSwipeEnds() {
        let app = configuredApp()
        app.launch()

        let simpleMode = app.buttons["SIMPLE"]
        XCTAssertTrue(simpleMode.waitForExistence(timeout: 4))
        tapClearOfDock(simpleMode)
        let syncAlert = app.alerts["APEX"]
        if syncAlert.waitForExistence(timeout: 2) { syncAlert.buttons["OK"].tap() }

        let card = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
                "completed-workout-", "completed-workout-delete-"
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilVisible(card, in: app, attempts: 12))

        card.swipeLeft()
        let collapsedDelete = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "completed-workout-delete-")
        ).firstMatch
        XCTAssertTrue(collapsedDelete.waitForExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 0.75)
        XCTAssertTrue(collapsedDelete.exists, "the revealed delete tray must remain open after the finger lifts")
        XCTAssertTrue(collapsedDelete.isHittable)
    }

    func testMorningCheckAcceptsWeightWithoutForcingASleepScore() {
        let app = configuredApp()
        app.launch()

        let simpleMode = app.buttons["SIMPLE"]
        XCTAssertTrue(simpleMode.waitForExistence(timeout: 4))
        simpleMode.tap()
        let syncAlert = app.alerts["APEX"]
        if syncAlert.waitForExistence(timeout: 2) {
            syncAlert.buttons["OK"].tap()
        }

        let morningCheck = app.buttons["morning-check-summary"]
        XCTAssertTrue(scrollUntilVisible(morningCheck, in: app, attempts: 6))
        morningCheck.tap()

        let sleepScore = app.textFields["morning-sleep-score"]
        let weight = app.textFields["morning-weight"]
        XCTAssertTrue(sleepScore.waitForExistence(timeout: 2))
        XCTAssertTrue(weight.waitForExistence(timeout: 2))
        let emptyScore = sleepScore.value as? String
        XCTAssertTrue(emptyScore == nil || emptyScore == "" || emptyScore == "%")

        weight.tap()
        weight.typeText("87.4")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        let dismissKeyboard = app.buttons["morning-keyboard-dismiss"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 2))
        dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))

        let save = app.buttons["morning-save"]
        XCTAssertTrue(scrollUntilVisible(save, in: app, attempts: 4))
        save.tap()
        XCTAssertTrue(morningCheck.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Morning check, 0"].exists)
        capture("morning-check-weight-only")
    }

    func testWaterQuickAddDismissesAnEmptyNumericKeyboardAndKeepsSettingsAtTheBottom() {
        let app = configuredApp()
        app.launchArguments.append("-apex-ui-test-open-water")
        app.launch()

        let simpleMode = app.buttons["SIMPLE"]
        XCTAssertTrue(simpleMode.waitForExistence(timeout: 4))
        simpleMode.tap()
        let syncAlert = app.alerts["APEX"]
        if syncAlert.waitForExistence(timeout: 2) {
            syncAlert.buttons["OK"].tap()
        }
        XCTAssertTrue(app.staticTexts["Water quick add"].waitForExistence(timeout: 5))

        let field = app.textFields["hydration-custom-ml"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        let add = app.buttons["hydration-custom-add"]
        XCTAssertTrue(add.exists)
        XCTAssertFalse(add.isEnabled)

        let hideKeyboard = app.buttons["hydration-keyboard-dismiss"]
        XCTAssertTrue(hideKeyboard.waitForExistence(timeout: 2))
        hideKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["hydration-settings-bottom"].exists)
        XCTAssertFalse(app.buttons["hydration-settings-top"].exists)
        capture("water-quick-add-refined")
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            configuredApp().launch()
        }
    }

    func testTrainingCalendarShowsPrescriptionAndHonestEmptyDay() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
        let main = app.buttons["portal.main"]
        XCTAssertTrue(scrollUntilVisible(main, in: app))
        main.tap()

        /* The muscle renderer owns drags across the large centre card. Start
           above it so this journey scrolls the enclosing programme view. */
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            )

        let today = calendarKey(offset: 0)
        let weekday = Calendar.current.component(.weekday, from: Date())
        let emptyDay = calendarKey(offset: weekday == 1 ? -1 : 1)
        let todayCell = app.buttons["calendar-day-\(today)"]
        XCTAssertTrue(scrollUntilVisible(todayCell, in: app))
        XCTAssertTrue(todayCell.label.contains("Scheduled"), todayCell.label)

        let emptyCell = app.buttons["calendar-day-\(emptyDay)"]
        XCTAssertTrue(emptyCell.exists)
        XCTAssertTrue(emptyCell.label.contains("No prescription"), emptyCell.label)
        capture("training-calendar-states")
        emptyCell.tap()

        XCTAssertTrue(app.staticTexts["No workout prescribed"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No programme was authored for this date."].exists)
        XCTAssertFalse(app.staticTexts["Rest day"].exists)
        capture("training-calendar-no-prescription")
    }

    func testSessionBriefingShowsMovementKnowledgeAndSessionContext() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
        let main = app.buttons["portal.main"]
        XCTAssertTrue(scrollUntilVisible(main, in: app))
        main.tap()

        let briefing = app.buttons["session-briefing-open"]
        XCTAssertTrue(scrollUntilVisible(briefing, in: app, attempts: 12))
        briefing.tap()

        let sessionContext = app.descendants(matching: .any)["session-briefing-context"]
        XCTAssertTrue(scrollUntilVisible(sessionContext, in: app, attempts: 12))

        let lessonOpeners = [
            "Strength and bodyweight work improve",
            "Mobility work can change",
            "Yoga here is practice",
            "An isometric builds strength",
            "A carry links grip",
            "Steady cardio is its own",
            "Recovery makes hard intervals",
            "Easy recovery work may change",
        ]
        XCTAssertTrue(lessonOpeners.contains { opener in
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", opener)
            ).firstMatch.exists
        })
        capture("session-briefing-movement-knowledge")
    }

    func testCustomWorkoutBuilderExposesTheCanonicalLibraryAndSelectsASportMovement() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
        let training = app.buttons["portal.transition"]
        XCTAssertTrue(training.waitForExistence(timeout: 4))
        XCTAssertTrue(scrollUntilVisible(training, in: app))
        tapClearOfDock(training)

        let build = app.buttons["custom-workout-build"]
        XCTAssertTrue(build.waitForExistence(timeout: 4))
        XCTAssertTrue(scrollUntilVisible(build, in: app, attempts: 12))
        tapClearOfDock(build)

        let count = app.staticTexts["custom-workout-result-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 4))
        XCTAssertEqual(count.label, "549 movements")
        capture("custom-workout-full-catalog")

        let search = app.textFields["custom-workout-search"]
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("Power Snatch")

        let result = app.buttons["custom-workout-item-power_snatch"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(result.waitForNonExistence(timeout: 3))
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 3),
            "Selecting a movement should dismiss the keyboard so the builder remains usable."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["custom-workout-selected-power_snatch"]
                .waitForExistence(timeout: 3)
        )
        capture("custom-workout-sport-movement-selected")
    }

    func testMealComposerPreservesFoodMemoryAndPresetWorkflow() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        app.buttons["portal.nutrition"].tap()

        let breakfast = app.staticTexts["meal-dayline-title-breakfast"]
        XCTAssertTrue(scrollUntilVisible(breakfast, in: app))
        tapClearOfDock(breakfast)

        XCTAssertTrue(app.buttons["meal-food-picker-open"].waitForExistence(timeout: 3))
        let composerName = app.textFields["meal-composer-name"]
        XCTAssertTrue(composerName.exists)
        XCTAssertTrue(app.descendants(matching: .any)["meal-total-water"].waitForExistence(timeout: 2))
        let compactItemWater = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "meal-item-card-", "millilitres water"
            )
        ).firstMatch
        /* Overlapping Dayline cards used to hand the tap to a neighbouring
           meal, which then failed further down for the wrong reason. */
        XCTAssertEqual(composerName.value as? String, "Breakfast", "tapped breakfast, opened something else")
        /* The presets card sits below the fold inside a lazy stack, so it is not
           built until the sheet is scrolled to it. */
        XCTAssertTrue(scrollUntilVisible(app.staticTexts["FAST STARTS"], in: app))
        XCTAssertTrue(app.buttons["Select"].firstMatch.waitForExistence(timeout: 3))

        /* The sticky save bar overlaps the lower edge of a merely "hittable"
           card in XCTest. Move the row into clear space before proving X. */
        app.swipeUp()
        let compactDelete = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "meal-item-card-", "Remove "
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilVisible(compactDelete, in: app))
        XCTAssertTrue(compactDelete.isHittable)
        XCTAssertTrue(compactItemWater.exists)
        compactDelete.tap()
        let compactUndo = app.descendants(matching: .any)["meal-item-undo"]
        XCTAssertTrue(compactUndo.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["1 food"].exists)
        capture("meal-composer-undo")
        compactUndo.tap()
        XCTAssertFalse(compactUndo.exists)
        capture("meal-composer-compact")

        let displayControl = app.segmentedControls.firstMatch
        XCTAssertTrue(displayControl.waitForExistence(timeout: 2))
        displayControl.buttons["Expanded"].tap()
        XCTAssertTrue(app.switches["Adaptive"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Lock"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "meal-item-card-", "millilitres water"
            )
        ).firstMatch.exists)
        app.swipeUp()
        let expandedDelete = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "meal-item-card-", "Remove "
            )
        ).firstMatch
        XCTAssertTrue(scrollUntilVisible(expandedDelete, in: app))
        XCTAssertTrue(expandedDelete.isHittable)
        expandedDelete.tap()
        let expandedUndo = app.descendants(matching: .any)["meal-item-undo"]
        XCTAssertTrue(expandedUndo.waitForExistence(timeout: 2))
        expandedUndo.tap()
        capture("meal-composer-expanded")

        app.buttons["Select"].tap()
        let firstFoodName = app.staticTexts["Swiss rolled oats"]
        XCTAssertTrue(firstFoodName.waitForExistence(timeout: 2))
        let firstFood = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                firstFoodName.identifier, "circle"
            )
        ).firstMatch
        XCTAssertTrue(firstFood.waitForExistence(timeout: 2))
        firstFood.tap()
        XCTAssertTrue(app.buttons["Create preset"].isEnabled)
        /* The count label lands a frame after the button enables. */
        XCTAssertTrue(app.descendants(matching: .any)["meal-selection-count"].waitForExistence(timeout: 3))
        capture("meal-composer-selection")
    }

    func testNutritionDaylineShowsTheCompletedWorkoutAndRecoveryContext() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        app.buttons["portal.nutrition"].tap()

        let recovery = app.staticTexts["Protein opportunity is open"]
        XCTAssertTrue(scrollUntilVisible(recovery, in: app))
        XCTAssertTrue(isReachable(recovery))

        let workout = app.staticTexts["Workout completed"]
        XCTAssertTrue(scrollUntilVisible(workout, in: app))
        XCTAssertEqual(workout.label, "Workout completed")
        capture("nutrition-dayline-workout-recovery")
    }

    func testCompactMealMillilitreUnitStaysOnOneLineInsideItsCard() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        app.buttons["portal.nutrition"].tap()

        let breakfast = app.staticTexts["meal-dayline-title-breakfast"]
        XCTAssertTrue(scrollUntilVisible(breakfast, in: app))
        tapClearOfDock(breakfast)

        let unitControls = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "meal-item-unit-")
        )
        let millilitres = unitControls.element(boundBy: 1)
        XCTAssertTrue(millilitres.waitForExistence(timeout: 2))
        for _ in 0..<8 where !millilitres.frame.intersects(app.frame) {
            app.swipeUp()
        }
        XCTAssertTrue(millilitres.frame.intersects(app.frame))
        XCTAssertTrue(millilitres.label.localizedCaseInsensitiveContains("ml"))

        let cardIdentifier = millilitres.identifier.replacingOccurrences(
            of: "meal-item-unit-", with: "meal-item-card-"
        )
        let cardElements = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", cardIdentifier)
        ).allElementsBoundByIndex
        XCTAssertGreaterThan(cardElements.count, 1)
        let cardFrame = cardElements.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        XCTAssertGreaterThanOrEqual(millilitres.frame.width, 60)
        XCTAssertLessThanOrEqual(millilitres.frame.height, 44)
        XCTAssertGreaterThanOrEqual(millilitres.frame.minY, cardFrame.minY - 1)
        XCTAssertLessThanOrEqual(millilitres.frame.maxY, cardFrame.maxY + 1)
        XCTAssertLessThanOrEqual(cardFrame.height, 96)
    }

    func testMealComposerBarcodeButtonOpensScannerWithoutOpeningFoodMemory() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        app.buttons["portal.nutrition"].tap()
        let breakfast = app.staticTexts["meal-dayline-title-breakfast"]
        XCTAssertTrue(scrollUntilVisible(breakfast, in: app))
        tapClearOfDock(breakfast)

        let scanner = app.buttons["meal-barcode-scanner-open"]
        XCTAssertTrue(scrollUntilVisible(scanner, in: app))
        scanner.tap()

        XCTAssertTrue(app.staticTexts["SCAN FOOD BARCODE"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Food Memory"].exists)
    }

    func testFoodAmountDecimalPadHasDoneAndCanAddFood() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.buttons["portal.nutrition"].waitForExistence(timeout: 4))
        app.buttons["portal.nutrition"].tap()
        let breakfast = app.staticTexts["meal-dayline-title-breakfast"]
        XCTAssertTrue(scrollUntilVisible(breakfast, in: app))
        /* Target the actual breakfast row title. The timeline container also
           exposes a combined button label, but its frame spans the full card
           and can land on another row after the scroll settles. */
        tapClearOfDock(breakfast)
        XCTAssertTrue(app.staticTexts["Build this meal"].waitForExistence(timeout: 3))

        let picker = app.buttons["meal-food-picker-open"]
        XCTAssertTrue(scrollUntilVisible(picker, in: app))
        picker.tap()
        let search = app.textFields["food-memory-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Food Memory"].buttons["Search"].exists)
        search.tap()
        search.typeText("protein")
        let food = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "food-row-")
        ).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 3))
        food.tap()

        let amountHeading = app.staticTexts["CONFIGURE AMOUNT"]
        XCTAssertTrue(amountHeading.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(amountHeading.frame.minX, app.frame.minX + 16)
        XCTAssertLessThanOrEqual(amountHeading.frame.maxX, app.frame.maxX - 16)

        let quantity = app.textFields["food-amount-quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 2))
        quantity.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        quantity.typeText("7")
        XCTAssertEqual(search.value as? String, "protein", "typing an amount must not remain bound to Food Memory search")
        XCTAssertTrue(
            String(describing: quantity.value).contains("7"),
            "the amount field must own keyboard input after the configurator opens"
        )
        XCTAssertTrue(app.buttons["food-amount-keyboard-done"].waitForExistence(timeout: 2))
        capture("food-amount-keyboard-done")
        app.buttons["food-amount-keyboard-done"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        let confirm = app.buttons["food-amount-confirm"]
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.minX, app.frame.minX + 16)
        XCTAssertLessThanOrEqual(confirm.frame.maxX, app.frame.maxX - 16)
        confirm.tap()
        XCTAssertFalse(app.descendants(matching: .any)["food-amount-quantity"].exists)
    }

    func testWorkoutPlayerGuidesAndRecordsActualSet() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
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

    func testAlreadyFinishedPausesAndCompletesWithoutInventingSets() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
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
        let recovery = app.buttons["workout-already-finished"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 2))
        recovery.tap()

        XCTAssertTrue(app.buttons["workout-already-finished-choose-wearable"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Did you finish this planned workout on your own?"].exists)
        app.buttons["workout-already-finished-cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-phase-warmup"].waitForExistence(timeout: 3))

        recovery.tap()
        let withoutWearable = app.buttons["workout-already-finished-without-wearable"]
        XCTAssertTrue(withoutWearable.waitForExistence(timeout: 3))
        withoutWearable.tap()

        let done = app.buttons["workout-receipt-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "external completion should open the normal receipt")
        XCTAssertTrue(app.staticTexts["Stats at a glance"].exists)
        capture("workout-already-finished-receipt")
        done.tap()
    }

    /// A finished session used to save and vanish. The receipt is the only
    /// place the load reported during the workout is handed back.
    func testFinishingAWorkoutShowsTheReceipt() {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(expandFitnessPlan(in: app))
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

    func testQuarantinedSyncWorkIsVisibleInsteadOfPretendingEverythingSynced() {
        let app = configuredApp()
        app.launchArguments.append("-apex-ui-test-failed-sync")
        app.launch()

        let simpleMode = app.buttons["SIMPLE"]
        XCTAssertTrue(simpleMode.waitForExistence(timeout: 4))
        tapClearOfDock(simpleMode)
        let syncAlert = app.alerts["APEX"]
        if syncAlert.waitForExistence(timeout: 2) {
            syncAlert.buttons["OK"].tap()
        }

        let warning = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "needs attention")
        ).firstMatch
        XCTAssertTrue(
            scrollUntilVisible(warning, in: app, attempts: 20),
            "a quarantined write must remain visible on the daily surface"
        )
        XCTAssertFalse(app.staticTexts["Synced"].exists)
        warning.tap()

        XCTAssertTrue(app.navigationBars["Sync issues"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Meal change"].exists)
        XCTAssertTrue(app.staticTexts["The server rejected this change."].exists)

        let technicalReason = app.buttons[
            "sync-technical-reason-b72e51d1-5d0b-4585-b361-9af511f98964"
        ]
        XCTAssertTrue(technicalReason.exists)
        technicalReason.tap()
        XCTAssertTrue(app.staticTexts["UI fixture: server rejected this write"].exists)

        app.buttons["Done"].tap()
        let advancedMode = app.buttons["ADVANCED"]
        XCTAssertTrue(advancedMode.waitForExistence(timeout: 3))
        tapClearOfDock(advancedMode)
        let advancedWarning = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "needs attention")
        ).firstMatch
        XCTAssertTrue(
            scrollUntilVisible(advancedWarning, in: app, attempts: 20),
            "Advanced mode must expose the same quarantined-write details"
        )
        XCTAssertFalse(app.staticTexts["Synced"].exists)
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

    /// Opens the Fitness Plan disclosure and leaves it open.
    @discardableResult
    private func expandFitnessPlan(in app: XCUIApplication) -> Bool {
        let toggle = app.buttons["portal.fitness-plan"]
        guard scrollUntilVisible(toggle, in: app), isReachable(toggle) else { return false }
        if toggle.value as? String == "Expanded" { return true }
        tapClearOfDock(toggle)
        let expanded = NSPredicate(format: "value == %@", "Expanded")
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: expanded, object: toggle)],
            timeout: 4
        ) == .completed
    }

    /// Opens a collapsible section and leaves it open. The disclosure's unique
    /// accessibility identifier and value are a stable contract; visible copy
    /// can be duplicated or remain outside the accessibility viewport.
    @discardableResult
    private func expandSection(
        _ id: String,
        in app: XCUIApplication
    ) -> Bool {
        let toggle = app.buttons["section-toggle-\(id)"]
        guard scrollUntilVisible(toggle, in: app), isReachable(toggle) else { return false }
        /* The open/closed state persists between launches, so never blind-tap:
           that would close a section a previous run left open. */
        if toggle.value as? String == "Expanded" { return true }
        toggle.tap()
        let expanded = NSPredicate(format: "value == %@", "Expanded")
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: expanded, object: toggle)],
            timeout: 4
        ) == .completed
    }

    @discardableResult
    private func collapseSection(_ id: String, in app: XCUIApplication) -> Bool {
        let toggle = app.buttons["section-toggle-\(id)"]
        guard scrollUntilVisible(toggle, in: app), isReachable(toggle) else { return false }
        if toggle.value as? String == "Collapsed" { return true }
        toggle.tap()
        let collapsed = NSPredicate(format: "value == %@", "Collapsed")
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: collapsed, object: toggle)],
            timeout: 4
        ) == .completed
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
        for _ in 0..<attempts {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.68))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.48))
            start.press(
                forDuration: 0.05,
                thenDragTo: end,
                withVelocity: 200,
                thenHoldForDuration: 0
            )
            let settled = XCTestExpectation(description: "incremental scroll settled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { settled.fulfill() }
            _ = XCTWaiter().wait(for: [settled], timeout: 1)
            if isReachable(element) { return true }
        }
        return element.firstMatch.exists
    }

    private func scrollUpUntilVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 20
    ) -> Bool {
        if isReachable(element) { return true }
        for _ in 0..<attempts {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.48))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.68))
            start.press(
                forDuration: 0.05,
                thenDragTo: end,
                withVelocity: 200,
                thenHoldForDuration: 0
            )
            let settled = XCTestExpectation(description: "incremental reverse scroll settled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { settled.fulfill() }
            _ = XCTWaiter().wait(for: [settled], timeout: 1)
            if isReachable(element) { return true }
        }
        return isReachable(element)
    }

    /// Large phase cards need each drag to settle before the next one starts;
    /// otherwise XCTest queues flicks faster than the outer ScrollView can move.
    private func scrollUntilReachableSettled(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int
    ) -> Bool {
        if isReachable(element) { return true }
        let outerScrollView = app.scrollViews.firstMatch
        for _ in 0..<attempts {
            outerScrollView.swipeUp()
            let settled = XCTestExpectation(description: "phase scroll settled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { settled.fulfill() }
            _ = XCTWaiter().wait(for: [settled], timeout: 1)
            if isReachable(element) { return true }
        }
        return isReachable(element)
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
        let firstPortalTile = app.buttons["portal.avatar"]
        func firstTileIsOnScreen() -> Bool {
            guard firstPortalTile.exists else { return false }
            let frame = firstPortalTile.frame
            return frame.width > 0
                && frame.height > 0
                && frame.minY >= app.frame.minY
                && frame.maxY <= app.frame.maxY
        }

        if firstTileIsOnScreen() { return }
        for _ in 0..<8 {
            app.swipeDown()
            if firstTileIsOnScreen() { return }
        }
        XCTFail("Avatar must become reachable when returning to the top of Advanced")
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
