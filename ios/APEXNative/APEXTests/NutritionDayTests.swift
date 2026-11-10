import XCTest
@testable import APEX

/// One bodyweight: the newest weigh-in this build can date feeds every target, and stored rows are reconciled when read.
@MainActor
final class NutritionDayTests: XCTestCase {
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!
    private let programDay = UUID()

    /// A calendar day relative to the real today, which is what the app's own accessors read.
    private func day(_ offset: Int) -> String {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!.apexDateKey
    }

    private func profile(weight: Double = 80) -> Profile {
        Profile(
            id: owner, userID: owner, persona: .iulian, profileKind: .standard, bespokeProtocolID: nil,
            displayName: "Test User", sex: "male", weightKG: weight, bodyFatPercent: nil, bodyFatSource: nil,
            bodyFatMeasuredAt: nil, customBMR: nil, heightCM: 180, birthdate: "1996-01-01",
            activityLevel: .moderate, goal: .maintain, targetKcal: nil, targetProteinG: nil,
            targetFatG: nil, targetCarbsG: nil, trainingTime: "07:00", baselineDate: "2026-01-01",
            profileNote: "", seedVersion: 1, calibrationK: 1, calibrationHistory: [],
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func data(weight: Double = 80) -> DashboardData {
        var data = DashboardData()
        data.profile = profile(weight: weight)
        data.settings = UserSettings(
            userID: owner, voiceOn: false, ticksOn: false, notificationsOn: false, guardianFactor: 1, addons: [:]
        )
        return data
    }

    /// A day's log with a weight on it. `closed` is a day the app finalised or closed with a run.
    private func weighIn(_ date: String, _ kg: Double?, closed: Bool = false) -> DailyLog {
        DailyLog(
            id: UUID(), userID: owner, date: date, kcal: nil, proteinG: nil, fatG: nil, carbsG: nil, waterL: 0,
            estimatedTDEE: closed ? 2_600 : nil, computedPAL: closed ? 1.5 : nil,
            activityMode: closed ? "precise" : "quick", weightKG: kg
        )
    }

    private func health(_ date: String, _ kg: Double) -> HealthMetric {
        HealthMetric(id: UUID(), userID: owner, date: date, weightKG: kg)
    }

    private func workout(_ date: String) -> WorkoutSession {
        WorkoutSession(
            id: UUID(), userID: owner, date: date, programDayID: programDay, isLite: false, isDeload: false,
            isEventRecovery: false, completed: true, qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
        )
    }

    private func reportBodyweight(_ data: DashboardData, on date: String) -> Double? {
        var fixture = data
        let session = workout(date)
        fixture.workoutSessions = [session]
        let end = max(day(0), date)
        return AvatarReport.scoped(
            ownerID: owner, data: fixture, partialScores: [:], period: .allTime,
            dates: min(day(-30), date)...end, today: end
        ).bodyweightBySession[session.id]
    }

    private func waterTarget(_ data: DashboardData) -> Int {
        DailyWaterTargets(data: data, coachManaged: false, followsCoach: false, includeCustom: false)
            .resolve(day: day(0), now: Date()).targetML
    }

    // MARK: Targets

    func testTheLatestWeighInFeedsEveryTarget() throws {
        var weighed = data()
        XCTAssertEqual(weighed.weighedProfile()?.weightKG, 80, "With no weigh-in the profile's weight stands")
        weighed.dailyLogs = [weighIn(day(-9), 79), weighIn(day(0), 76)]
        XCTAssertEqual(weighed.weighedProfile()?.weightKG, 76)
        XCTAssertEqual(weighed.profile?.weightKG, 80, "The stored profile is read, never rewritten")

        // An account weighed at 76 kg is fed exactly like one set up at 76 kg.
        let setUp = data(weight: 76)
        let targets = EnergyEngine.targets(profile: try XCTUnwrap(weighed.weighedProfile()), logs: [], catalog: [])
        XCTAssertEqual(targets, EnergyEngine.targets(profile: try XCTUnwrap(setUp.profile), logs: [], catalog: []))
        XCTAssertEqual(targets.proteinG, 144, "1.9 g per kg of 76 kg, not of the 80 kg it was set up with")

        XCTAssertEqual(
            FitnessBrainService.engineInput(from: weighed)?.profile.weightKG, 76,
            "The Avatar grades against the same bodyweight"
        )
        XCTAssertEqual(waterTarget(weighed), waterTarget(setUp), "So does the water goal")

        var meal = weighed
        meal.loggedMeals = [LoggedMeal(
            id: UUID(), userID: owner, localDate: day(0), mealSlot: "lunch", displayName: "Meal",
            sourcePresetID: nil, sourcePlannedMealID: nil, loggedAt: "\(day(0))T12:00:00Z",
            clientIdempotencyKey: UUID().uuidString, loggedAs: "manual",
            totalKcal: 700, totalProteinG: 40, totalCarbsG: 0, totalFatG: 0
        )]
        let report = try XCTUnwrap(NutritionReport.summarize(ownerID: owner, data: meal, dates: day(0)...day(0)))
        XCTAssertEqual(report.macros.first { $0.kind == .protein }?.target, 144, "And the nutrition report")
    }

    func testThisMorningsEntryOutranksAnOlderHealthReading() {
        var fixture = data()
        fixture.healthMetrics = [health(day(-7), 82)]
        fixture.dailyLogs = [weighIn(day(0), 79.5)]
        XCTAssertEqual(fixture.weighedProfile()?.weightKG, 79.5)
        XCTAssertEqual(reportBodyweight(fixture, on: day(0)), 79.5)

        // Older builds saved the newest Health reading again on every later day. It is one reading.
        fixture.healthMetrics = (-7...0).map { health(day($0), 82) }
        XCTAssertEqual(fixture.weighedProfile()?.weightKG, 79.5, "A week-old reading repeated onto today is still a week old")
        XCTAssertEqual(reportBodyweight(fixture, on: day(0)), 79.5, "The report agrees")
        XCTAssertEqual(reportBodyweight(fixture, on: day(-3)), 82, "Before this morning the reading stands")

        // A scale reading and a typed entry on the same morning: the person's own entry is the one kept.
        fixture.healthMetrics = [health(day(-7), 82), health(day(0), 79.2)]
        XCTAssertEqual(fixture.weighedProfile()?.weightKG, 79.5)
        XCTAssertEqual(reportBodyweight(fixture, on: day(0)), 79.5)
    }

    // MARK: Stored rows

    func testTheProfilesWeightCopiedOntoAClosedDayIsNotAWeighIn() {
        var fixture = data()
        fixture.dailyLogs = [
            weighIn("2026-11-12", 78.5),
            weighIn("2026-11-13", 80, closed: true),
            weighIn("2026-11-14", 78.4),
        ]
        XCTAssertEqual(
            Bodyweight.weighIns(ownerID: owner, data: fixture).map(\.kg), [78.5, 78.4],
            "The 80 kg written when the day was finalised repeats the profile; no scale said it"
        )
        XCTAssertEqual(reportBodyweight(fixture, on: "2026-11-13"), 78.5, "History reads the weigh-in before it")
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-14"), 78.4)

        // The newest weight on record may be the person confirming their weight in Settings, so it stands.
        fixture.dailyLogs.removeLast()
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-14"), 80)

        // The same figure typed on a day the app never closed is a weigh-in like any other.
        fixture.dailyLogs = [weighIn("2026-11-12", 78.5), weighIn("2026-11-13", 80), weighIn("2026-11-14", 78.4)]
        XCTAssertEqual(Bodyweight.weighIns(ownerID: owner, data: fixture).map(\.kg), [78.5, 80, 78.4])
    }

    func testAWeighInOutsideTheAccountOrInTheFutureIsIgnored() {
        var fixture = data()
        var foreign = weighIn(day(0), 60)
        foreign = DailyLog(
            id: foreign.id, userID: UUID(), date: foreign.date, waterL: 0, activityMode: "quick", weightKG: 60
        )
        fixture.dailyLogs = [foreign, weighIn(day(2), 70), weighIn(day(0), 5)]
        XCTAssertEqual(fixture.weighedProfile()?.weightKG, 80)
    }

    // MARK: Weights recorded before this build

    /// A day after the cut-over to read the bodyweight on, whatever the calendar says today.
    private let afterUpdating = "2026-12-01"

    private func bodyweight(_ data: DashboardData, on day: String) -> Double? {
        data.weighedProfile(on: day)?.weightKG
    }

    private func protein(_ data: DashboardData, on day: String) throws -> Int {
        EnergyEngine.targets(profile: try XCTUnwrap(data.weighedProfile(on: day)), logs: [], catalog: []).proteinG
    }

    func testUpdatingTheAppChangesNobodysTargets() throws {
        /* An account as older builds left it: weigh-ins, a day the app closed with the profile's
           weight on it, and one old Health reading saved again on every day it was imported,
           which carries on for as long as the old build is still in use. */
        var fixture = data()
        fixture.dailyLogs = [weighIn("2026-10-20", 76), weighIn("2026-11-02", 80, closed: true), weighIn("2026-11-09", 77)]
        fixture.healthMetrics = (1...12).map { health(String(format: "2026-11-%02d", $0), 95) }
        for day in ["2026-11-10", "2026-11-12", afterUpdating] {
            XCTAssertEqual(bodyweight(fixture, on: day), 80, "The weight the person gave stands on \(day)")
        }
        XCTAssertEqual(try protein(fixture, on: afterUpdating), 152, "1.9 g per kg of the profile's 80 kg, as before the update")
        XCTAssertEqual(
            Bodyweight.weighIns(ownerID: owner, data: fixture).map(\.kg), [76, 95, 77],
            "The weigh-in history is all still there for the report"
        )
    }

    func testATypedWeightIsNotReplacedByAnOlderHealthReading() {
        // A new account types 82 kg. Apple Health holds one 95 kg sample from 2023.
        var fixture = data(weight: 82)
        fixture.healthMetrics = [health("2023-05-01", 95)]
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 82)

        // Signing up leaves the typed weight on its day, so a reading sampled before that day stays behind it.
        fixture.dailyLogs = [weighIn("2026-11-20", 82)]
        fixture.healthMetrics.append(health("2026-11-15", 95))
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 82)
    }

    func testAWeightSetInSettingsAfterTheLastWeighInStands() {
        // Weighed in at 76 kg in October, then set to 80 kg in Settings on an older build, which dated nothing.
        var fixture = data()
        fixture.dailyLogs = [weighIn("2026-10-20", 76)]
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 80)

        // From this build a Settings change is a weigh-in of its own day, so it is ordered like any other.
        fixture.dailyLogs = [weighIn("2026-11-12", 76), weighIn("2026-11-15", 80)]
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-14"), 76)
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 80)
    }

    func testTheNextWeighInAfterUpdatingMovesTheTargets() throws {
        var fixture = data()
        fixture.dailyLogs = [weighIn("2026-10-20", 78), weighIn("2026-11-12", 76)]
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-11"), 80, "Until then the profile's weight stands")
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-12"), 76)
        XCTAssertEqual(try protein(fixture, on: afterUpdating), 144, "1.9 g per kg of 76 kg")

        fixture.dailyLogs = [weighIn("2026-11-10", 75)]
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-10"), 75, "A weigh-in on the first day of this build counts")
    }

    func testAHealthReadingAfterTheLastTypedWeightIsUsed() {
        var fixture = data(weight: 82)
        fixture.dailyLogs = [weighIn("2026-11-11", 82)]
        fixture.healthMetrics = [health("2026-11-10", 83), health("2026-11-13", 84)]
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-12"), 82, "A reading sampled before the typed weight stays behind it")
        XCTAssertEqual(bodyweight(fixture, on: "2026-11-13"), 84)
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 84)

        fixture.dailyLogs.append(weighIn("2026-11-13", 83.5))
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 83.5, "The person's own entry outranks a reading of the same day")
    }

    func testAWeightTheTargetsCannotUseNeverBecomesTheBodyweight() throws {
        // A slip of the finger in the weight field, then a Health sample no scale would give.
        var fixture = data()
        fixture.dailyLogs = [weighIn("2026-11-12", 78), weighIn("2026-11-14", 27)]
        fixture.healthMetrics = [health("2026-11-15", 310)]
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 78, "The last weight the targets accept stands")
        let targets = EnergyEngine.targets(
            profile: try XCTUnwrap(fixture.weighedProfile(on: afterUpdating)), logs: [], catalog: []
        )
        XCTAssertTrue(targets.reviewReasons.isEmpty, "One wrong entry does not block the day's targets")
        XCTAssertEqual(targets.proteinG, 148, "1.9 g per kg of 78 kg")
        XCTAssertEqual(
            Bodyweight.weighIns(ownerID: owner, data: fixture).map(\.kg), [78, 27, 310],
            "What was entered is still on its day"
        )

        fixture.dailyLogs = [weighIn("2026-11-14", 27)]
        fixture.healthMetrics = []
        XCTAssertEqual(bodyweight(fixture, on: afterUpdating), 80, "With nothing usable since, the profile's weight stands")

        // The edges of what the targets accept are weights like any other.
        for edge in [30.0, 300.0] {
            fixture.dailyLogs = [weighIn("2026-11-14", edge)]
            XCTAssertEqual(bodyweight(fixture, on: afterUpdating), edge)
        }
    }

    // MARK: Writes, through a local sandbox session

    private func sandbox() throws -> (AppSession, AccountOperationLease) {
        let session = AppSession(developerSandboxRole: .coach)
        let operation = try XCTUnwrap(session.accountOperationLease())
        session.data.dailyLogs = []
        session.data.healthMetrics = []
        return (session, operation)
    }

    func testFinalisingADayLeavesItsWeightAlone() async throws {
        let (session, operation) = try sandbox()
        let profile = try XCTUnwrap(session.profile)
        let targets = EnergyEngine.targets(profile: profile, logs: [], catalog: [])
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))

        try await session.finalizeActivityDay(yesterday, targets: targets, operation: operation)
        let closed = try XCTUnwrap(session.data.dailyLogs.first { $0.date == yesterday.apexDateKey })
        XCTAssertEqual(closed.estimatedTDEE, targets.tdee)
        XCTAssertNil(closed.weightKG, "Nobody stepped on a scale: the day gets no weight")

        try await session.saveMorningWeight(profile.weightKG - 1.5, on: Date(), operation: operation)
        try await session.finalizeActivityDay(Date(), targets: targets, operation: operation)
        XCTAssertEqual(
            session.data.dailyLogs.first { $0.date == Date().apexDateKey }?.weightKG, profile.weightKG - 1.5,
            "A weigh-in already on the day is kept"
        )
    }

    func testAWeightSetInSettingsIsTodaysWeighInAndEverythingFollowsIt() async throws {
        let (session, operation) = try sandbox()
        let stored = try XCTUnwrap(session.data.profile?.weightKG)
        try await session.saveMorningWeight(stored - 3, on: Date(), operation: operation)
        XCTAssertEqual(session.data.weighedProfile()?.weightKG, stored - 3, "The targets read the weigh-in")
        XCTAssertEqual(session.data.profile?.weightKG, stored, "The stored profile is untouched")

        // Changing something else on the profile must not write the weigh-in into it.
        try await session.setGoal(.bulk, operation: operation)
        XCTAssertEqual(session.data.profile?.weightKG, stored)

        try await session.stepBodyweight(by: 2, operation: operation)
        XCTAssertEqual(session.data.weighedProfile()?.weightKG, stored - 1, "A weight set in Settings is the newest on record")
        XCTAssertEqual(session.data.profile?.weightKG, stored - 1)
        XCTAssertEqual(session.data.dailyLogs.first { $0.date == Date().apexDateKey }?.weightKG, stored - 1)
    }

    func testTheWeightTypedAtSignUpIsThatDaysWeighIn() async throws {
        let session = AppSession(developerSandboxRole: .individual)
        let operation = try XCTUnwrap(session.accountOperationLease())
        session.data.dailyLogs = []
        session.data.healthMetrics = []
        var input = TrainingInduction.Input(startDate: Date().apexDateKey)
        input.bodyBaseline = .init(sex: "male", weightKG: 82, heightCM: 180, birthdate: "1990-01-01")
        input.dataConsent = .init(
            termsVersion: TrainingInduction.currentTermsVersion,
            privacyVersion: TrainingInduction.currentPrivacyVersion, acceptedAt: Date().ISO8601Format()
        )
        input.avatarStartingPoints = AvatarStartingPoints.balanced
        await session.skipRemainingInduction(input, operation: operation)
        XCTAssertNil(session.alertMessage)
        XCTAssertEqual(session.data.profile?.weightKG, 82)
        XCTAssertEqual(
            session.data.dailyLogs.filter { $0.userID == operation.ownerID && $0.date == Date().apexDateKey }.map(\.weightKG), [82],
            "The typed weight is dated, so a later reading can be ordered against it"
        )
    }

    func testQuickStepperTapsEachBuildOnTheOneBefore() async throws {
        let (session, operation) = try sandbox()
        let stored = try XCTUnwrap(session.data.profile?.weightKG)
        func today() -> Double? { session.data.dailyLogs.first { $0.date == Date().apexDateKey }?.weightKG }

        // Three taps before the screen redraws, each its own task as the stepper starts them.
        let taps = (0..<3).map { _ in Task { try await session.stepBodyweight(by: 0.5, operation: operation) } }
        for tap in taps { try await tap.value }
        XCTAssertEqual(session.data.weighedProfile()?.weightKG, stored + 1.5, "No tap is lost")
        XCTAssertEqual(today(), stored + 1.5)
        XCTAssertEqual(session.data.profile?.weightKG, stored + 1.5, "The profile ends on the same weight")

        // The stepper stays inside what the targets accept, so it can never block them.
        try await session.stepBodyweight(by: -500, operation: operation)
        XCTAssertEqual(session.data.weighedProfile()?.weightKG, 30)
        try await session.stepBodyweight(by: 500, operation: operation)
        XCTAssertEqual(session.data.weighedProfile()?.weightKG, 300)
        XCTAssertEqual(today(), 300)
    }

    func testTheSettingsStepperHandsOverItsStepAndTheWeighInIsWrittenFirst() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/SettingsView.swift"), encoding: .utf8
        ).filter { !$0.isWhitespace }
        XCTAssertTrue(
            settings.contains("session.stepBodyweight(by:delta,operation:operation)"),
            "The tap hands over the step, and the session adds it to the weight on record at that moment"
        )
        XCTAssertFalse(
            settings.contains("bodyweight+delta"),
            "The weight on screen when the tap began is stale by the second tap"
        )

        // A save waits on the disk and the network. The weigh-in, which the next tap reads, must be on the day before that.
        let session = try String(contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift"), encoding: .utf8)
        let start = try XCTUnwrap(session.range(of: "func stepBodyweight("))
        let end = try XCTUnwrap(session.range(of: "func saveMorningWeight(", range: start.upperBound..<session.endIndex))
        let step = String(session[start.lowerBound..<end.lowerBound])
        let weighIn = try XCTUnwrap(step.range(of: "saveMorningWeight("))
        let profile = try XCTUnwrap(step.range(of: "updateProfile("))
        XCTAssertLessThan(weighIn.lowerBound, profile.lowerBound)
    }

    func testThePlanBriefingsWaterFigureReadsTheOneBodyweight() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let panel = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Training/TrainingInductionPanel.swift"), encoding: .utf8
        )
        let start = try XCTUnwrap(panel.range(of: "private func makeBriefing("))
        let end = try XCTUnwrap(panel.range(of: "private func openCurrentBriefing(", range: start.upperBound..<panel.endIndex))
        let briefing = String(panel[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(
            briefing.contains("let profile = session.data.weighedProfile()"),
            "The briefing's daily water is worked out from the bodyweight the water card uses"
        )
        XCTAssertFalse(briefing.contains("session.profile"), "The stored profile's weight is not the one bodyweight")
    }

    // MARK: The planned-meal tap

    func testLoggingAPlannedMealWritesTheDayOnScreenAndLeavesTodayAlone() async throws {
        let (session, operation) = try sandbox()
        let meal = Meal(
            id: UUID(), userID: operation.ownerID, time: "13:00", name: "Lunch", foods: "", kcal: 700,
            proteinG: 45, fatG: 20, carbsG: 80, fullDaysOnly: false, sortOrder: 99
        )
        session.data.meals.append(meal)
        let prescription = AdaptiveMeal(source: meal, kcal: 700, proteinG: 45, fatG: 20, carbsG: 80, portionNote: "")
        let browsedDay = "2021-03-04"
        let browsed = try XCTUnwrap(ISO8601DateFormatter.apexDateOnly.date(from: browsedDay)).addingTimeInterval(12 * 3_600)
        let today = Date().apexDateKey
        func ticked(_ day: String) -> Bool {
            session.data.mealLogs.contains { $0.date == day && $0.mealID == meal.id }
        }
        func logged(_ day: String) -> [LoggedMeal] {
            session.data.loggedMeals.filter { $0.localDate == day && $0.sourcePlannedMealID == meal.id }
        }

        try await session.togglePlannedMeal(prescription, on: browsed, operation: operation)
        XCTAssertTrue(ticked(browsedDay))
        XCTAssertEqual(logged(browsedDay).map(\.totalProteinG), [45])
        XCTAssertFalse(ticked(today), "Today is not the day on screen")
        XCTAssertTrue(logged(today).isEmpty)

        // A second tap takes it back off that day, and still leaves today alone.
        try await session.togglePlannedMeal(prescription, on: browsed, operation: operation)
        XCTAssertFalse(ticked(browsedDay))
        XCTAssertTrue(logged(browsedDay).isEmpty)
        XCTAssertFalse(ticked(today))
    }

    func testTheHomeMealTapNamesTheDayOnScreen() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Portal/SimpleHomeView.swift"), encoding: .utf8
        ).filter { !$0.isWhitespace }
        XCTAssertTrue(
            home.contains("session.togglePlannedMeal(prescription,on:date,operation:operation)"),
            "The tap reads the browsed day, so it must write that day"
        )
        XCTAssertTrue(home.contains("letdate=selectedDateTask{do{tryawaitsession.togglePlannedMeal("))

        // No caller can fall back to today: the session asks for the day.
        let session = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift"), encoding: .utf8
        ).filter { !$0.isWhitespace }
        XCTAssertTrue(session.contains("functogglePlannedMeal(_prescription:AdaptiveMeal,ondate:Date,operation:"))
    }

    // MARK: The activity level

    func testAppleHealthSuggestsALevelAndNeverWritesIt() async throws {
        let (session, operation) = try sandbox()
        let today = Date().apexDateKey
        session.data.activityLogs.removeAll { $0.date == today }
        try await session.setActivityLevel(.light, operation: operation)
        func record(steps: Int, kcal: Int, minutes: Int) -> WearableActivityRecord {
            WearableActivityRecord(
                date: today, steps: steps, activeCalories: kcal, exerciseMinutes: minutes,
                source: "apple_health", updatedAt: Date().ISO8601Format()
            )
        }

        // The day's running totals arrive with every import: breakfast time, then after a long walk.
        await session.saveWearableActivity(record(steps: 300, kcal: 20, minutes: 0), operation: operation)
        XCTAssertEqual(session.data.profile?.activityLevel, .light, "A quiet morning does not lower the level")
        await session.saveWearableActivity(record(steps: 21_000, kcal: 1_500, minutes: 180), operation: operation)
        XCTAssertEqual(session.data.profile?.activityLevel, .light, "A hand-picked level stays until the person changes it")
        XCTAssertEqual(
            WearableActivityRecord.activeCalories(on: today, settings: session.data.settings, ownerID: operation.ownerID),
            1_500, "The day's record itself is saved"
        )

        // Taking the suggestion is the person's own action.
        let suggested = try XCTUnwrap(NutritionRecordedActivity.suggestion(
            profile: session.data.weighedProfile(), settings: session.data.settings,
            logs: session.data.activityLogs, date: today
        ))
        XCTAssertNotEqual(suggested, .light)
        await session.useSuggestedActivityLevel(on: today, operation: operation)
        XCTAssertEqual(session.data.profile?.activityLevel, suggested)
    }

    // MARK: The weight field

    func testTheWeightFieldShowsAndSavesInTheChosenUnit() throws {
        let locale = Locale(identifier: "en_GB")
        XCTAssertEqual(MorningCheckLogic.weightText(kilograms: 78, unit: .kilograms, locale: locale), "78.0")
        XCTAssertEqual(MorningCheckLogic.weightText(kilograms: 78, unit: .pounds, locale: locale), "172.0")

        // What the field shows is what it saves: 172 lb goes back in as 78 kg, not as 172 kg.
        let saved = try XCTUnwrap(MorningCheckLogic.entry(
            sleep: "", recovery: "", weight: "172.0", source: "apple", weightUnit: .pounds
        )?.weightKG)
        XCTAssertEqual(saved, 78, accuracy: 0.05)
        XCTAssertEqual(MorningCheckLogic.weightText(kilograms: 78.4, unit: .kilograms, locale: Locale(identifier: "de_DE")), "78,4")
    }

    // MARK: Past days keep the goals they had

    func testANewWeighInDoesNotRegradeTheDaysBeforeIt() throws {
        var fixture = data()
        let waterTargets = DailyWaterTargets(data: fixture, coachManaged: false, followsCoach: false, includeCustom: false)
        let before = try XCTUnwrap(FitnessBrainService.scoredInput(from: fixture, waterTargets: waterTargets, now: Date()))
        XCTAssertTrue(before.history.past.isEmpty)
        XCTAssertEqual(before.history.current?.weightKG, 80)

        // The first recalculation that sees a weigh-in, on an account with no goal history yet.
        fixture.dailyLogs = [weighIn(day(0), 76)]
        let scored = try XCTUnwrap(FitnessBrainService.scoredInput(from: fixture, waterTargets: waterTargets, now: Date()))
        XCTAssertEqual(scored.history.current?.weightKG, 76, "From today the weigh-in is the bodyweight")
        XCTAssertEqual(scored.history.current?.targets.proteinG, 144)
        XCTAssertEqual(scored.history.past.map(\.until), [day(0)])
        XCTAssertEqual(scored.history.past.first?.goals.weightKG, 80, "Earlier days keep the bodyweight they were graded with")
        XCTAssertEqual(scored.input.pastTargets.first?.1.proteinG, 152)
    }

    // MARK: Cost

    func testTwoYearsOfWaterDaysWorkOutTheBodyweightOnce() throws {
        /* Two years of days, each with water, a typed weigh-in and a Health reading. All of it
           predates this build, so the bodyweight is the profile's with or without the weights. */
        let first = try XCTUnwrap(ISO8601DateFormatter.apexDateOnly.date(from: "2024-01-01"))
        let days = try (0..<730).map {
            try XCTUnwrap(Calendar.current.date(byAdding: .day, value: $0, to: first)).apexDateKey
        }
        var weighed = data()
        weighed.dailyLogs = days.enumerated().map { index, date in
            var log = weighIn(date, 78 + Double(index % 20) / 10)
            log.waterL = 2
            return log
        }
        weighed.healthMetrics = days.enumerated().map { index, date in health(date, 79 + Double(index % 30) / 10) }
        var unweighed = weighed
        for index in unweighed.dailyLogs.indices { unweighed.dailyLogs[index].weightKG = nil }
        for index in unweighed.healthMetrics.indices { unweighed.healthMetrics[index].weightKG = nil }

        func waterGoals(_ data: DashboardData) throws -> [String: Int] {
            let targets = DailyWaterTargets(data: data, coachManaged: false, followsCoach: false, includeCustom: false)
            return try XCTUnwrap(FitnessBrainService.scoredInput(from: data, waterTargets: targets, now: Date()))
                .input.hydrationByDay.mapValues(\.targetML)
        }
        let goals = try waterGoals(weighed)
        XCTAssertEqual(goals.count, 730)
        XCTAssertEqual(goals, try waterGoals(unweighed), "Every day's water goal is the one it had")

        /* Each day is graded against the bodyweight its goals already carry. Sorting every
           weigh-in again for each of the 730 added seconds to every change of the data, on the
           main thread. What the weigh-ins add is now held to a few such sorts. The quickest of
           several interleaved runs is compared, so a busy machine cannot fail it. */
        var withWeights = Duration.seconds(60), without = withWeights, oneSort = withWeights
        for _ in 0..<5 {
            withWeights = min(withWeights, try ContinuousClock().measure { _ = try waterGoals(weighed) })
            without = min(without, try ContinuousClock().measure { _ = try waterGoals(unweighed) })
            oneSort = min(oneSort, ContinuousClock().measure { _ = weighed.weighedProfile() })
        }
        XCTAssertLessThan(withWeights, without + oneSort * 20, "The bodyweight is worked out once, not once per water day")
    }
}
