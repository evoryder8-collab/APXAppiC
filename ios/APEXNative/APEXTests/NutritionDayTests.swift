import XCTest
@testable import APEX

/// One bodyweight: the newest weigh-in feeds every target, and stored rows are reconciled when read.
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
        return AvatarReport.scoped(
            ownerID: owner, data: fixture, partialScores: [:], period: .allTime,
            dates: day(-30)...day(0), today: day(0)
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
        weighed.dailyLogs = [weighIn(day(-9), 79), weighIn(day(-1), 76)]
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
            weighIn(day(-3), 78.5),
            weighIn(day(-2), 80, closed: true),
            weighIn(day(-1), 78.4),
        ]
        XCTAssertEqual(
            Bodyweight.weighIns(ownerID: owner, data: fixture).map(\.kg), [78.5, 78.4],
            "The 80 kg written when the day was finalised repeats the profile; no scale said it"
        )
        XCTAssertEqual(reportBodyweight(fixture, on: day(-2)), 78.5, "History reads the weigh-in before it")
        XCTAssertEqual(fixture.weighedProfile()?.weightKG, 78.4)

        // The newest weight on record may be the person confirming their weight in Settings, so it stands.
        fixture.dailyLogs.removeLast()
        XCTAssertEqual(fixture.weighedProfile()?.weightKG, 80)

        // The same figure typed on a day the app never closed is a weigh-in like any other.
        fixture.dailyLogs = [weighIn(day(-3), 78.5), weighIn(day(-2), 80), weighIn(day(-1), 78.4)]
        XCTAssertEqual(Bodyweight.weighIns(ownerID: owner, data: fixture).map(\.kg), [78.5, 80, 78.4])
    }

    func testAWeighInOutsideTheAccountOrInTheFutureIsIgnored() {
        var fixture = data()
        var foreign = weighIn(day(-1), 60)
        foreign = DailyLog(
            id: foreign.id, userID: UUID(), date: foreign.date, waterL: 0, activityMode: "quick", weightKG: 60
        )
        fixture.dailyLogs = [foreign, weighIn(day(2), 70), weighIn(day(-4), 5)]
        XCTAssertEqual(fixture.weighedProfile()?.weightKG, 80)
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
        try await session.saveMorningWeight(stored - 3, on: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -5, to: Date())), operation: operation)
        XCTAssertEqual(session.data.weighedProfile()?.weightKG, stored - 3, "The targets read the weigh-in")
        XCTAssertEqual(session.data.profile?.weightKG, stored, "The stored profile is untouched")

        // Changing something else on the profile must not write the weigh-in into it.
        try await session.setGoal(.bulk, operation: operation)
        XCTAssertEqual(session.data.profile?.weightKG, stored)

        try await session.setBodyweight(stored - 1, operation: operation)
        XCTAssertEqual(session.data.weighedProfile()?.weightKG, stored - 1, "A weight set in Settings is the newest on record")
        XCTAssertEqual(session.data.profile?.weightKG, stored - 1)
        XCTAssertEqual(session.data.dailyLogs.first { $0.date == Date().apexDateKey }?.weightKG, stored - 1)
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
        fixture.dailyLogs = [weighIn(day(-1), 76)]
        let scored = try XCTUnwrap(FitnessBrainService.scoredInput(from: fixture, waterTargets: waterTargets, now: Date()))
        XCTAssertEqual(scored.history.current?.weightKG, 76, "From today the weigh-in is the bodyweight")
        XCTAssertEqual(scored.history.current?.targets.proteinG, 144)
        XCTAssertEqual(scored.history.past.map(\.until), [day(0)])
        XCTAssertEqual(scored.history.past.first?.goals.weightKG, 80, "Earlier days keep the bodyweight they were graded with")
        XCTAssertEqual(scored.input.pastTargets.first?.1.proteinG, 152)
    }
}
