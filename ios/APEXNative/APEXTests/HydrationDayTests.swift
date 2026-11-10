import XCTest
@testable import APEX

/// Water and supplement writes land on the day the screen shows, driven through a local sandbox session.
@MainActor
final class HydrationDayTests: XCTestCase {
    private let emptyDay = "2021-03-04"

    private func sandbox() throws -> (AppSession, AccountOperationLease) {
        let session = AppSession(developerSandboxRole: .coach)
        let operation = try XCTUnwrap(session.accountOperationLease())
        session.data.supplements = ["Creatine", "Magnesium"].enumerated().map { index, name in
            Supplement(id: UUID(), userID: operation.ownerID, name: name, dose: "", timing: "morning", clockTime: nil,
                       offsetMinutes: nil, groupLabel: "Morning", trainingDaysOnly: false, sortOrder: index)
        }
        return (session, operation)
    }

    private func date(_ day: String, hour: Int = 12) throws -> Date {
        let start = try XCTUnwrap(ISO8601DateFormatter.apexDateOnly.date(from: day))
        return try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: hour, to: start))
    }

    private func ticked(_ session: AppSession, on day: String) -> Set<UUID> {
        Set(session.data.supplementLogs.filter { $0.date == day }.map(\.supplementID))
    }

    func testRemovingTheDaysOnlyDrinkLeavesNoWaterBehind() async throws {
        let (session, operation) = try sandbox()
        let day = try date(emptyDay)
        try await session.logHydration(amountML: 250, on: day, operation: operation)
        XCTAssertEqual(session.hydrationResolution(on: day).drinkML, 250)

        let drink = try XCTUnwrap(session.data.hydrationEvents?.first { $0.localDate == emptyDay })
        try await session.deleteHydrationEvent(drink, on: day, operation: operation)

        XCTAssertEqual(session.hydrationResolution(on: day).drinkML, 0)
        XCTAssertEqual(session.data.dailyLogs.first { $0.date == emptyDay }?.waterL, 0)

        // The next drink stands alone: the removed one does not return as a legacy entry.
        try await session.logHydration(amountML: 330, on: day, operation: operation)
        XCTAssertEqual(session.hydrationResolution(on: day).drinkML, 330)
        XCTAssertEqual(session.data.hydrationEvents?.filter { $0.localDate == emptyDay }.map(\.amountML), [330])
    }

    func testADrinkAddedWhileARemovalIsStillSavingDoesNotBringTheRemovedDrinkBack() async throws {
        let (session, operation) = try sandbox()
        let day = try date(emptyDay)
        try await session.logHydration(amountML: 250, on: day, operation: operation)
        let drink = try XCTUnwrap(session.data.hydrationEvents?.first { $0.localDate == emptyDay })

        // The next drink is added before the server has answered the removal.
        session.sandboxDeleteInFlight = { [weak session] in
            session?.sandboxDeleteInFlight = nil
            try? await session?.logHydration(amountML: 330, on: day, operation: operation)
        }
        try await session.deleteHydrationEvent(drink, on: day, operation: operation)

        XCTAssertEqual(session.hydrationResolution(on: day).drinkML, 330)
        XCTAssertEqual(session.data.hydrationEvents?.filter { $0.localDate == emptyDay }.map(\.amountML), [330])
        XCTAssertEqual(session.data.dailyLogs.first { $0.date == emptyDay }?.waterL, 0.33)
    }

    func testAfterMidnightTheAppIsOnTheNewDayUnlessTheUserBrowsedBack() async throws {
        let (session, operation) = try sandbox()
        let evening = try date("2031-05-10", hour: 21)
        let morning = try date("2031-05-11", hour: 7)
        session.browsingDate = evening
        session.followTodayAcrossMidnight(now: evening)
        XCTAssertEqual(session.browsingDate.apexDateKey, "2031-05-10")

        session.followTodayAcrossMidnight(now: morning)
        XCTAssertEqual(session.browsingDate.apexDateKey, "2031-05-11", "left on today, so it opens on the new day")

        // A morning drink and a supplement tick are saved to the new day.
        try await session.logHydration(amountML: 250, on: session.browsingDate, operation: operation)
        XCTAssertEqual(session.hydrationResolution(on: morning).drinkML, 250)
        XCTAssertEqual(session.hydrationResolution(on: evening).drinkML, 0)
        let supplement = try XCTUnwrap(session.activeSupplements.first)
        try await session.toggleSupplement(supplement, on: session.browsingDate, operation: operation)
        XCTAssertEqual(ticked(session, on: "2031-05-11"), [supplement.id])
        XCTAssertTrue(ticked(session, on: "2031-05-10").isEmpty)

        // A day the user deliberately browsed back to stays put over the next midnight.
        session.browsingDate = evening
        session.followTodayAcrossMidnight(now: try date("2031-05-12", hour: 7))
        XCTAssertEqual(session.browsingDate.apexDateKey, "2031-05-10")
    }

    func testAWorkoutOpenAcrossMidnightKeepsItsDayUntilItCloses() throws {
        let (session, _) = try sandbox()
        let evening = try date("2031-05-10", hour: 23)
        let afterMidnight = try date("2031-05-11", hour: 0)
        session.browsingDate = evening
        session.followTodayAcrossMidnight(now: evening)

        // The workout opens at 23:00 and is still open when the day changes.
        session.holdBrowsingDate(true, now: evening)
        session.followTodayAcrossMidnight(now: afterMidnight)
        XCTAssertEqual(session.browsingDate.apexDateKey, "2031-05-10", "the open workout keeps the day it was started on")

        // Closing it catches up with the day that began meanwhile.
        session.holdBrowsingDate(false, now: afterMidnight)
        XCTAssertEqual(session.browsingDate.apexDateKey, "2031-05-11")

        // The next midnight is followed as before.
        session.followTodayAcrossMidnight(now: try date("2031-05-12", hour: 7))
        XCTAssertEqual(session.browsingDate.apexDateKey, "2031-05-12")
    }

    func testReopeningTheAppTheNextMorningMovesOffYesterday() async throws {
        let (session, _) = try sandbox()
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        session.browsingDate = yesterday
        session.followTodayAcrossMidnight(now: yesterday)

        await session.onAppBecameActive()

        XCTAssertEqual(session.browsingDate.apexDateKey, Date().apexDateKey)
    }

    func testMarkGroupDoneTicksTheDayOnScreenAndLeavesTodayAlone() async throws {
        let (session, operation) = try sandbox()
        let group = Array(session.activeSupplements.prefix(2))
        XCTAssertEqual(group.count, 2)
        let ids = Set(group.map(\.id))
        let today = Date()
        let browsed = try date(emptyDay)
        for supplement in group where !ticked(session, on: today.apexDateKey).contains(supplement.id) {
            try await session.toggleSupplement(supplement, on: today, operation: operation)
        }
        let todayBefore = ticked(session, on: today.apexDateKey)
        XCTAssertTrue(todayBefore.isSuperset(of: ids))

        // Nothing ticked on the browsed day: the group is ticked there.
        try await session.toggleSupplementGroup(group, on: browsed, operation: operation)
        XCTAssertEqual(ticked(session, on: emptyDay), ids)
        XCTAssertEqual(ticked(session, on: today.apexDateKey), todayBefore, "today's ticks are untouched")

        // One still open on the browsed day: the group completes it.
        try await session.toggleSupplement(group[0], on: browsed, operation: operation)
        try await session.toggleSupplementGroup(group, on: browsed, operation: operation)
        XCTAssertEqual(ticked(session, on: emptyDay), ids)

        // All ticked: the group clears that day and only that day.
        try await session.toggleSupplementGroup(group, on: browsed, operation: operation)
        XCTAssertTrue(ticked(session, on: emptyDay).isEmpty)
        XCTAssertEqual(ticked(session, on: today.apexDateKey), todayBefore)
    }

    func testThePhoneGaugeTheWatchAndTheScoreEngineGiveOneWaterTotalForADay() async throws {
        let (session, operation) = try sandbox()
        let day = try date(emptyDay)
        func watchTotal() -> Int {
            HydrationCompanionSnapshot.make(
                ownerID: operation.ownerID, date: emptyDay, events: session.data.hydrationEvents ?? [], presets: [],
                preferences: .default,
                legacyDrinkLiters: session.data.dailyLogs.first { $0.date == emptyDay }?.waterL ?? 0,
                revision: "\(emptyDay)T12:00:00.000Z"
            ).totalML
        }
        func scoreEngineTotal() -> Int? {
            FitnessBrainService.waterTotals(session.data, ownerID: operation.ownerID)[emptyDay]
        }

        try await session.logHydration(amountML: 2_400, on: day, operation: operation)
        let foods = try await session.searchFoods(query: "Oats", operation: operation)
        try await session.logFood(try XCTUnwrap(foods.first), amount: 100, unit: "g", mealSlot: "breakfast", date: day, operation: operation)
        // Food water logged after the food event last synced: the phone and the engine both count it.
        let entry = try XCTUnwrap(session.data.loggedFoodEntries.indices.last)
        session.data.loggedFoodEntries[entry].waterML = 349.6
        XCTAssertEqual(session.hydrationIntakeML(on: day), 2_750)
        XCTAssertEqual(scoreEngineTotal(), 2_750)

        // Once the food event holds it, the Watch receives the same figure.
        session.data.hydrationEvents?.removeAll { $0.localDate == emptyDay && $0.kind == .food }
        session.data.hydrationEvents?.append(HydrationEvent(
            id: UUID(), userID: operation.ownerID, clientIdempotencyKey: "food:\(emptyDay)", localDate: emptyDay,
            occurredAt: "\(emptyDay)T12:00:00Z", amountML: 350, kind: .food, paletteToken: "food", iconToken: "fork.knife",
            source: .food, healthKitSampleID: nil, createdAt: "\(emptyDay)T12:00:00Z", updatedAt: "\(emptyDay)T12:00:00Z"
        ))
        XCTAssertEqual(session.hydrationIntakeML(on: day), 2_750)
        XCTAssertEqual(watchTotal(), 2_750)
        XCTAssertEqual(scoreEngineTotal(), 2_750)

        // A very wet day is the same number everywhere, not capped on the phone alone.
        try await session.logHydration(amountML: 4_000, on: day, operation: operation)
        XCTAssertEqual(session.hydrationIntakeML(on: day), 6_750)
        XCTAssertEqual(watchTotal(), 6_750)
        XCTAssertEqual(scoreEngineTotal(), 6_750)
    }

    func testTheGaugeAndTheScoreEngineRoundFoodWaterToTheSameMillilitre() async throws {
        let (session, operation) = try sandbox()
        let day = try date(emptyDay)
        func scoreEngineTotal() -> Int? {
            FitnessBrainService.waterTotals(session.data, ownerID: operation.ownerID)[emptyDay]
        }
        try await session.logHydration(amountML: 2_250, on: day, operation: operation)
        let foods = try await session.searchFoods(query: "Oats", operation: operation)
        try await session.logFood(try XCTUnwrap(foods.first), amount: 400, unit: "g", mealSlot: "breakfast", date: day, operation: operation)
        let entry = try XCTUnwrap(session.data.loggedFoodEntries.indices.last)
        XCTAssertEqual(session.data.loggedFoodEntries[entry].equivalentAmount, 400)

        // Food water ending on half a millilitre: the gauge rounds it up as the engine does, so a 2,751 ml goal is met on both.
        session.data.loggedFoodEntries[entry].waterML = 500.5
        XCTAssertEqual(scoreEngineTotal(), 2_751)
        XCTAssertEqual(session.hydrationIntakeML(on: day), 2_751)

        // A portion worked out from water per 100 g is rounded the way the engine rounds it.
        session.data.loggedFoodEntries[entry].waterML = nil
        session.data.loggedFoodEntries[entry].snapshotWaterML100 = 87.374
        XCTAssertEqual(scoreEngineTotal(), 2_600)
        XCTAssertEqual(session.hydrationIntakeML(on: day), 2_600)
    }
}
