import XCTest
@testable import APEX

final class SessionBriefingKnowledgeTests: XCTestCase {
    func testClassifiesEveryMovementKnowledgeFamilyFromCatalogueMetadata() {
        let context = makeContext(exerciseNames: [
            "Romanian Deadlift",
            "Pull-Up",
            "Couch Stretch",
            "Downward-Facing Dog",
            "Plank",
            "Farmer's Carry",
            "Stationary Bike",
            "Burpee",
        ])

        XCTAssertEqual(context.movementFamilies, [
            .strengthBodyweight,
            .mobility,
            .yoga,
            .isometric,
            .carry,
            .cardio,
            .interval,
        ])
    }

    func testPreservesFirstOccurrenceWhileRemovingDuplicateFamilies() {
        let context = makeContext(exerciseNames: [
            "Stationary Bike",
            "Romanian Deadlift",
            "Pull-Up",
            "Burpee",
            "Stationary Bike",
        ])

        XCTAssertEqual(context.movementFamilies, [
            .cardio,
            .strengthBodyweight,
            .interval,
        ])
    }

    func testRestWithoutMovementsUsesRecoveryButUnknownTrainingDoesNotGuess() {
        XCTAssertEqual(
            makeContext(dayType: "rest", exerciseNames: []).movementFamilies,
            [.recovery]
        )
        XCTAssertTrue(
            makeContext(dayType: "upper", exerciseNames: ["Unknown cached movement"])
                .movementFamilies.isEmpty
        )
    }

    func testPositionUsesCompletedSessionOnTheSelectedDate() {
        XCTAssertEqual(
            makeContext(
                date: "2026-08-28",
                completedSessionDates: ["2026-08-27", "2026-08-28"]
            ).position,
            .after
        )
        XCTAssertEqual(
            makeContext(
                date: "2026-08-29",
                completedSessionDates: ["2026-08-28"]
            ).position,
            .before
        )
    }

    func testExperienceBandsUseOnlyCompletedSessionHistory() {
        XCTAssertEqual(makeContext(completedSessionCount: 0).experience, .littleHistory)
        XCTAssertEqual(makeContext(completedSessionCount: 6).experience, .developingHistory)
        XCTAssertEqual(makeContext(completedSessionCount: 24).experience, .establishedHistory)
    }

    func testPersistedPainJointAndStructuredHypermobilitySignalsAreRead() {
        let addons: [String: JSONValue] = [
            "training_induction": .object([
                "pain_areas": .array([.string("knees")]),
            ]),
            "joint_checkins": .array([
                .object([
                    "date": .string("2026-08-20"),
                    "arms": .number(2),
                    "core": .number(2),
                    "legs": .number(3),
                ]),
                .object([
                    "date": .string("2026-08-27"),
                    "arms": .number(1),
                    "core": .number(4),
                    "legs": .number(2),
                ]),
            ]),
            "hypermobility_baseline": .object([
                "reported": .bool(true),
            ]),
        ]

        let context = makeContext(addons: addons)

        XCTAssertTrue(context.painReported)
        XCTAssertTrue(context.elevatedJointCheckIn)
        XCTAssertTrue(context.hypermobilityReported)
    }

    func testScalarHypermobilityCompatibilityAndSubthresholdJointCheckIn() {
        let addons: [String: JSONValue] = [
            "joint_checkins": .array([
                .object([
                    "date": .string("2026-08-27"),
                    "arms": .number(3),
                    "core": .number(3),
                    "legs": .number(3),
                ]),
            ]),
            "hypermobility_reported": .bool(true),
        ]

        let context = makeContext(addons: addons)

        XCTAssertFalse(context.elevatedJointCheckIn)
        XCTAssertTrue(context.hypermobilityReported)
    }

    func testJointCheckinOlderThanTwoWeeksStopsDrivingTheElevatedLine() {
        func context(checkedOn date: String) -> SessionBriefing.KnowledgeContext {
            makeContext(date: "2026-08-28", addons: [
                "joint_checkins": .array([
                    .object(["date": .string(date), "arms": .number(1), "core": .number(1), "legs": .number(7)]),
                ]),
            ])
        }

        XCTAssertTrue(context(checkedOn: "2026-08-14").elevatedJointCheckIn, "14 days old still counts")
        XCTAssertFalse(context(checkedOn: "2026-08-13").elevatedJointCheckIn, "15 days old no longer speaks for today")
        XCTAssertFalse(context(checkedOn: "2026-08-29").elevatedJointCheckIn, "a later check-in says nothing about this session")
    }

    func testSecondSessionOnTheSameDateIsNotAlreadyComplete() {
        let morning = UUID(), evening = UUID()
        var data = DashboardData.empty
        data.workoutSessions = [WorkoutSession(
            id: UUID(), userID: UUID(), date: "2026-08-28", programDayID: morning, isLite: false,
            isDeload: false, isEventRecovery: false, completed: true, qualityScore: 1,
            startedAt: nil, completedAt: nil, notes: ""
        )]
        func position(_ programDayID: UUID?, on date: String = "2026-08-28") -> SessionBriefing.SessionPosition {
            SessionBriefing.knowledgeContext(
                dayType: "legs_a", exerciseNames: [], date: date, programDayID: programDayID, data: data
            ).position
        }

        XCTAssertEqual(position(morning), .after)
        XCTAssertEqual(position(evening), .before, "another session finished that day does not finish this one")
        XCTAssertEqual(position(nil), .before, "a rest day has no session to be complete")
        XCTAssertEqual(position(morning, on: "2026-08-29"), .before)
    }

    func testEveryBriefingCardNamesTheSessionItDescribes() throws {
        let training = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "APEX/Features/Training")
        let callers = try ["TrainingProgramView.swift", "WorkoutDaySheet.swift"]
            .map { try String(contentsOf: training.appending(path: $0)) }.joined()
        let cards = callers.components(separatedBy: "MuscleMapCard(").count - 1

        XCTAssertEqual(cards, 4)
        XCTAssertEqual(callers.components(separatedBy: "sessionDayID: ").count - 1, cards)
        XCTAssertTrue(try String(contentsOf: training.appending(path: "MuscleMapCard.swift"))
            .contains("programDayID: sessionDayID,"))
    }

    func testMobilityKnowledgeTeachesMethodsBoundariesAndNeuralWarning() {
        let knowledge = SessionBriefing.knowledge(context: .init(
            position: .before,
            movementFamilies: [.mobility],
            movementNames: ["Couch Stretch"],
            painReported: false,
            elevatedJointCheckIn: false,
            hypermobilityReported: false,
            experience: .littleHistory
        ))

        XCTAssertTrue(knowledge.lessonKeys.contains(SessionBriefing.Copy.mobility))
        XCTAssertTrue(knowledge.lessonKeys.contains(SessionBriefing.Copy.mobilityMethods))
        XCTAssertTrue(knowledge.cautionKeys.contains(SessionBriefing.Copy.mobilityBoundary))
        XCTAssertTrue(knowledge.cautionKeys.contains(SessionBriefing.Copy.neuralWarning))
        XCTAssertEqual(knowledge.contextNoteKey, SessionBriefing.Copy.littleHistory)
    }

    func testRecoveryCorrectsMythsAndCompletedSessionUsesPostFrame() {
        let knowledge = SessionBriefing.knowledge(context: .init(
            position: .after,
            movementFamilies: [.recovery],
            movementNames: [],
            painReported: false,
            elevatedJointCheckIn: false,
            hypermobilityReported: false,
            experience: .establishedHistory
        ))

        XCTAssertEqual(knowledge.lessonKeys, [SessionBriefing.Copy.recovery])
        XCTAssertEqual(knowledge.contextNoteKey, SessionBriefing.Copy.afterSession)
    }

    func testKnowledgeCapsMovementLessonsAndOrdersCautions() {
        let knowledge = SessionBriefing.knowledge(context: .init(
            position: .before,
            movementFamilies: [.strengthBodyweight, .isometric, .carry, .cardio, .yoga],
            movementNames: [],
            painReported: true,
            elevatedJointCheckIn: true,
            hypermobilityReported: true,
            experience: .developingHistory
        ))

        XCTAssertEqual(knowledge.lessonKeys.count, 3)
        XCTAssertEqual(knowledge.cautionKeys, [
            SessionBriefing.Copy.hypermobility,
            SessionBriefing.Copy.reportedPain,
            SessionBriefing.Copy.elevatedJoint,
            SessionBriefing.Copy.yogaBoundary,
        ])
    }

    func testUnknownMovementProducesNoGuessedLesson() {
        let context = makeContext(
            dayType: "upper",
            exerciseNames: ["Unknown cached movement"]
        )

        XCTAssertTrue(SessionBriefing.knowledge(context: context).lessonKeys.isEmpty)
    }

    private func makeContext(
        dayType: String = "upper",
        exerciseNames: [String] = ["Romanian Deadlift"],
        date: String? = "2026-08-28",
        completedSessionDates: [String] = [],
        completedSessionCount: Int = 0,
        addons: [String: JSONValue]? = nil
    ) -> SessionBriefing.KnowledgeContext {
        SessionBriefing.knowledgeContext(
            dayType: dayType,
            exerciseNames: exerciseNames,
            date: date,
            completedSessionDates: completedSessionDates,
            completedSessionCount: completedSessionCount,
            addons: addons
        )
    }
}
