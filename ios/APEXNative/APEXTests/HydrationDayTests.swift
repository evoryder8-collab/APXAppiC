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

    func testReopeningTheAppTheNextMorningMovesOffYesterday() async throws {
        let (session, _) = try sandbox()
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        session.browsingDate = yesterday
        session.followTodayAcrossMidnight(now: yesterday)

        await session.onAppBecameActive()

        XCTAssertEqual(session.browsingDate.apexDateKey, Date().apexDateKey)
    }
}
