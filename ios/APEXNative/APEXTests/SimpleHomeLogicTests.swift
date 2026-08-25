import XCTest
@testable import APEX

final class SimpleHomeLogicTests: XCTestCase {
    func testInterfaceModeReadsSharedWebSettingsContract() {
        let userID = UUID()
        var settings = UserSettings(
            userID: userID,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.4,
            addons: [:]
        )

        XCTAssertEqual(PortalUIMode.current(from: settings), .advanced)
        settings.addons["uiMode"] = .string("simple")
        XCTAssertEqual(PortalUIMode.current(from: settings), .simple)
    }

    func testCompletionIsRoundedAndClamped() {
        XCTAssertEqual(SimpleHomeLogic.completion(completed: 0, total: 0), 100)
        XCTAssertEqual(SimpleHomeLogic.completion(completed: 2, total: 3), 67)
        XCTAssertEqual(SimpleHomeLogic.completion(completed: 12, total: 10), 100)
        XCTAssertEqual(SimpleHomeLogic.completion(completed: -1, total: 10), 0)
    }

    func testNextActionPrefersLatestDueThenEarliestUpcoming() {
        XCTAssertEqual(SimpleHomeLogic.nextCandidateIndex(times: [420, 720, 1_140], nowMinutes: 800), 1)
        XCTAssertEqual(SimpleHomeLogic.nextCandidateIndex(times: [420, 720, 1_140], nowMinutes: 300), 0)
        XCTAssertNil(SimpleHomeLogic.nextCandidateIndex(times: [], nowMinutes: 800))
    }

    func testBespokeAccountsProjectMainPhaseWithoutChangingOrdinaryAccounts() {
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .constantine,
                mainIsUsable: true,
                transitionIsUsable: true
            ),
            "main"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .june,
                mainIsUsable: true,
                transitionIsUsable: true
            ),
            "main"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .constantine,
                mainIsUsable: false,
                transitionIsUsable: true
            ),
            "transition"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .matthew,
                mainIsUsable: true,
                transitionIsUsable: true
            ),
            "transition"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .iulian,
                mainIsUsable: true,
                transitionIsUsable: false
            ),
            "main"
        )
    }

    func testSeededConstantineSimpleHomeResolvesTheMainWorkout() {
        let data = APEXDebugFixture.dashboard()
        let slug = SimpleHomeLogic.guidedProgramSlug(
            persona: data.profile?.persona,
            mainIsUsable: TrainingInduction.hasUsablePrescription(in: data, slug: "main"),
            transitionIsUsable: TrainingInduction.hasUsablePrescription(in: data, slug: "transition")
        )

        XCTAssertEqual(slug, "main")
        XCTAssertEqual(TrainingInduction.visibleProgramDays(in: data, slug: slug).map(\.name), ["Upper strength"])
    }

    func testCompletedTrainingOpensTheLatestReceiptForThatExactDayAndPrescription() {
        let userID = UUID()
        let dayID = UUID()
        let olderID = UUID()
        let latestID = UUID()
        let sessions = [
            WorkoutSession(
                id: olderID, userID: userID, date: "2026-08-21", programDayID: dayID,
                isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: "2026-08-21T17:00:00Z",
                completedAt: "2026-08-21T18:00:00Z", notes: ""
            ),
            WorkoutSession(
                id: UUID(), userID: userID, date: "2026-08-21", programDayID: dayID,
                isLite: false, isDeload: false, isEventRecovery: false, completed: false,
                qualityScore: 1, startedAt: "2026-08-21T19:00:00Z",
                completedAt: nil, notes: ""
            ),
            WorkoutSession(
                id: latestID, userID: userID, date: "2026-08-21", programDayID: dayID,
                isLite: true, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: "2026-08-21T19:30:00Z",
                completedAt: "2026-08-21T20:00:00Z", notes: ""
            ),
            WorkoutSession(
                id: UUID(), userID: userID, date: "2026-08-22", programDayID: dayID,
                isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
            ),
        ]

        XCTAssertEqual(
            SimpleHomeLogic.completedSessionID(
                sessions: sessions,
                date: "2026-08-21",
                programDayID: dayID
            ),
            latestID
        )
        XCTAssertNil(
            SimpleHomeLogic.completedSessionID(
                sessions: sessions,
                date: "2026-08-21",
                programDayID: UUID()
            )
        )
    }
}
