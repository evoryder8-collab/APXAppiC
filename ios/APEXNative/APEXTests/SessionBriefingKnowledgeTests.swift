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
