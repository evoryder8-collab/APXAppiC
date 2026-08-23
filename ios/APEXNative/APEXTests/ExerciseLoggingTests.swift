import XCTest
@testable import APEX

final class ExerciseLoggingTests: XCTestCase {
    func testNativeGeneratedCatalogueMatchesTheWebKindBreakdown() {
        var counts: [ExerciseLoggingKind: Int] = [:]
        for movement in MovementTiming.cataloguedMovements {
            let kind = ExerciseLogging.descriptor(for: movement).kind
            counts[kind, default: 0] += 1
        }

        XCTAssertEqual(MovementTiming.cataloguedMovements.count, 332)
        XCTAssertEqual(counts[.strength], 129)
        XCTAssertEqual(counts[.bodyweight], 79)
        XCTAssertEqual(counts[.isometric], 15)
        XCTAssertEqual(counts[.carry], 12)
        XCTAssertEqual(counts[.cardio], 15)
        XCTAssertEqual(counts[.mobility], 65)
        XCTAssertEqual(counts[.interval], 16)
        XCTAssertEqual(counts[.circuit], 1)
    }

    func testResolverClassifiesCanonicalMovementMetadataWithoutStoredKind() {
        let cases: [(String, ExerciseLoggingKind)] = [
            ("Romanian Deadlift", .strength),
            ("Pull-Up", .bodyweight),
            ("Plank", .isometric),
            ("Farmer's Carry", .carry),
            ("Stationary Bike", .cardio),
            ("Treadmill Walk", .cardio),
            ("Assault Bike Sprint", .cardio),
            ("ASSAULT BIKE SPRINT", .cardio),
            ("Couch Stretch", .mobility),
            ("Burpee", .interval),
            ("Sun Salutation A", .circuit),
        ]

        for (name, expected) in cases {
            XCTAssertEqual(
                ExerciseLogging.descriptor(movementNamed: name).kind,
                expected,
                name
            )
        }
    }

    func testDescriptorsExposeOnlyFactsThatMovementCanProduce() {
        XCTAssertEqual(
            ExerciseLogging.descriptor(movementNamed: "Pull-Up").fields,
            [.reps, .signedLoad, .rir]
        )
        XCTAssertEqual(
            ExerciseLogging.descriptor(movementNamed: "Box Jump").fields,
            [.contacts]
        )
        XCTAssertEqual(
            ExerciseLogging.descriptor(movementNamed: "Plank").fields,
            [.duration, .signedLoad]
        )
        XCTAssertEqual(
            ExerciseLogging.descriptor(movementNamed: "Farmer's Carry").fields,
            [.duration, .distance, .signedLoad]
        )
        XCTAssertEqual(
            ExerciseLogging.descriptor(movementNamed: "Stationary Bike").fields,
            [.duration, .distance]
        )
        XCTAssertEqual(
            ExerciseLogging.descriptor(movementNamed: "Couch Stretch").fields,
            [.duration, .completion]
        )
        XCTAssertEqual(
            ExerciseLogging.descriptor(movementNamed: "Burpee").fields,
            [.rounds, .work, .recovery]
        )
        XCTAssertFalse(ExerciseLogging.descriptor(movementNamed: "Sun Salutation A").isSupported)
    }

    func testPaceIsDerivedOnlyFromDistanceAndDuration() {
        XCTAssertEqual(
            ExerciseLogging.derivedPaceSecondsPerKilometre(
                distanceMeters: 5_000,
                durationSeconds: 1_500
            ),
            300
        )
        XCTAssertNil(
            ExerciseLogging.derivedPaceSecondsPerKilometre(
                distanceMeters: 0,
                durationSeconds: 1_500
            )
        )
        XCTAssertNil(
            ExerciseLogging.derivedPaceSecondsPerKilometre(
                distanceMeters: 5_000,
                durationSeconds: 0
            )
        )
        XCTAssertEqual(
            ExerciseLogging.factSummary(log(
                exerciseName: "Stationary Bike",
                durationSeconds: 1_500,
                distanceMeters: 5_000
            )).last,
            "5:00 /km"
        )
    }

    func testStrengthAndBodyweightProgressUseOneSignedLoadAxis() {
        let strength = ExerciseLogging.descriptor(movementNamed: "Romanian Deadlift")
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 50, reps: 8),
                current: log(weightKG: 50, reps: 9),
                descriptor: strength
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 50, reps: 8),
                current: log(weightKG: 52.5, reps: 8),
                descriptor: strength
            ),
            .improved
        )

        let bodyweight = ExerciseLogging.descriptor(movementNamed: "Pull-Up")
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: -20, reps: 5),
                current: log(weightKG: -15, reps: 5),
                descriptor: bodyweight
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 0, reps: 5),
                current: log(weightKG: 5, reps: 5),
                descriptor: bodyweight
            ),
            .improved
        )
    }

    func testIsometricAndCarryProgressRequireNoDoseRegression() {
        let isometric = ExerciseLogging.descriptor(movementNamed: "Plank")
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 10, durationSeconds: 30),
                current: log(weightKG: 10, durationSeconds: 35),
                descriptor: isometric
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 10, durationSeconds: 30),
                current: log(weightKG: 12, durationSeconds: 30),
                descriptor: isometric
            ),
            .improved
        )

        let carry = ExerciseLogging.descriptor(movementNamed: "Farmer's Carry")
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 24, distanceMeters: 20),
                current: log(weightKG: 24, distanceMeters: 25),
                descriptor: carry
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 24, durationSeconds: 30),
                current: log(weightKG: 28, durationSeconds: 30),
                descriptor: carry
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 24, distanceMeters: 20),
                current: log(weightKG: 24, durationSeconds: 30),
                descriptor: carry
            ),
            .incomparable
        )
    }

    func testCardioProgressDerivesPerformanceFromTwoMeasuredFacts() {
        let cardio = ExerciseLogging.descriptor(movementNamed: "Stationary Bike")
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(durationSeconds: 1_500, distanceMeters: 5_000),
                current: log(durationSeconds: 1_440, distanceMeters: 5_000),
                descriptor: cardio
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(durationSeconds: 1_500, distanceMeters: 5_000),
                current: log(durationSeconds: 1_500, distanceMeters: 5_200),
                descriptor: cardio
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(durationSeconds: 1_800, distanceMeters: 5_000),
                current: log(durationSeconds: 3_000, distanceMeters: 10_000),
                descriptor: cardio
            ),
            .improved
        )
    }

    func testStrengthProgressRequiresReportedEffortAndComparableLoad() {
        let strength = ExerciseLogging.descriptor(movementNamed: "Romanian Deadlift")
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: 80, reps: 8, rir: nil),
                current: log(weightKG: 80, reps: 9, rir: nil),
                descriptor: strength
            ),
            .incomparable
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(weightKG: nil, reps: 8, rir: 2),
                current: log(weightKG: 80, reps: 8, rir: 2),
                descriptor: strength
            ),
            .incomparable
        )
    }

    func testIntervalProgressRespectsRoundsWorkAndRecovery() {
        let interval = ExerciseLogging.descriptor(movementNamed: "Burpee")
        let baseline = log(rounds: 8, workSeconds: 30, recoverySeconds: 30)

        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: baseline,
                current: log(rounds: 9, workSeconds: 30, recoverySeconds: 30),
                descriptor: interval
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: baseline,
                current: log(rounds: 8, workSeconds: 35, recoverySeconds: 30),
                descriptor: interval
            ),
            .improved
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: baseline,
                current: log(rounds: 8, workSeconds: 30, recoverySeconds: 25),
                descriptor: interval
            ),
            .improved
        )
    }

    func testProductionHistoryPathReportsCardioProgressFromPreviousMatchingSet() {
        let userID = UUID()
        let oldSessionID = UUID()
        let newSessionID = UUID()
        let previous = log(
            userID: userID,
            sessionID: oldSessionID,
            exerciseName: "Stationary Bike",
            movementID: "cycle_stationary",
            durationSeconds: 1_500,
            distanceMeters: 5_000
        )
        let current = log(
            userID: userID,
            sessionID: newSessionID,
            exerciseName: "Stationary Bike",
            movementID: "cycle_stationary",
            durationSeconds: 1_440,
            distanceMeters: 5_000
        )
        var data = DashboardData.empty
        data.workoutSessions = [
            session(id: oldSessionID, userID: userID, date: "2026-08-20"),
            session(id: newSessionID, userID: userID, date: "2026-08-23")
        ]
        data.workoutLogs = [previous, current]

        XCTAssertEqual(ProgressionEngine.latestProgress(data, current: current), .improved)
    }

    func testProductionHistoryLazilyMatchesLegacyAliasToCanonicalMovementID() {
        let userID = UUID()
        let oldSessionID = UUID()
        let newSessionID = UUID()
        let previous = log(
            userID: userID,
            sessionID: oldSessionID,
            exerciseName: "Pull Ups (different grip)",
            weightKG: 0,
            reps: 8,
            rir: 2
        )
        let current = log(
            userID: userID,
            sessionID: newSessionID,
            exerciseName: "Pull-Up",
            movementID: "pull_up",
            weightKG: 0,
            reps: 9,
            rir: 2
        )
        var data = DashboardData.empty
        data.workoutSessions = [
            session(id: oldSessionID, userID: userID, date: "2026-08-20"),
            session(id: newSessionID, userID: userID, date: "2026-08-23")
        ]
        data.workoutLogs = [previous, current]

        XCTAssertEqual(ProgressionEngine.latestProgress(data, current: current), .improved)
    }

    func testMobilityAndContactWorkProduceAdherenceWithoutAutomaticOverload() {
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(durationSeconds: 30),
                current: log(durationSeconds: 45),
                descriptor: ExerciseLogging.descriptor(movementNamed: "Couch Stretch")
            ),
            .adherence
        )
        XCTAssertEqual(
            ProgressionEngine.compare(
                previous: log(reps: 5),
                current: log(reps: 8),
                descriptor: ExerciseLogging.descriptor(movementNamed: "Box Jump")
            ),
            .adherence
        )
    }

    func testSupplementaryLoadAndRIRCannotCompleteAnOtherwiseBlankSet() {
        let strength = ExerciseLogging.descriptor(movementNamed: "Romanian Deadlift")
        XCTAssertFalse(ExerciseLogging.hasPrimaryFacts(
            descriptor: strength, reps: nil, durationSeconds: nil, distanceMeters: nil,
            contacts: nil, rounds: nil, workSeconds: nil
        ))
        XCTAssertTrue(ExerciseLogging.hasPrimaryFacts(
            descriptor: strength, reps: 8, durationSeconds: nil, distanceMeters: nil,
            contacts: nil, rounds: nil, workSeconds: nil
        ))

        let carry = ExerciseLogging.descriptor(movementNamed: "Farmer's Carry")
        XCTAssertFalse(ExerciseLogging.hasPrimaryFacts(
            descriptor: carry, reps: nil, durationSeconds: nil, distanceMeters: nil,
            contacts: nil, rounds: nil, workSeconds: nil
        ))
        XCTAssertTrue(ExerciseLogging.hasPrimaryFacts(
            descriptor: carry, reps: nil, durationSeconds: nil, distanceMeters: 20,
            contacts: nil, rounds: nil, workSeconds: nil
        ))

        let interval = ExerciseLogging.descriptor(movementNamed: "Burpee")
        XCTAssertFalse(ExerciseLogging.hasPrimaryFacts(
            descriptor: interval, reps: nil, durationSeconds: nil, distanceMeters: nil,
            contacts: nil, rounds: nil, workSeconds: 30
        ))
        XCTAssertFalse(ExerciseLogging.hasPrimaryFacts(
            descriptor: interval, reps: nil, durationSeconds: nil, distanceMeters: nil,
            contacts: nil, rounds: 8, workSeconds: 30
        ))
        XCTAssertTrue(ExerciseLogging.hasPrimaryFacts(
            descriptor: interval, reps: nil, durationSeconds: nil, distanceMeters: nil,
            contacts: nil, rounds: 8, workSeconds: 30, recoverySeconds: 20
        ))
    }

    func testSharedSaveBoundaryRequiresCompleteFactsForEveryKind() {
        XCTAssertFalse(ExerciseLogging.isValid(input(
            name: "Stationary Bike", durationSeconds: 600
        )))
        XCTAssertTrue(ExerciseLogging.isValid(input(
            name: "Stationary Bike", durationSeconds: 600, distanceMeters: 3_000
        )))
        XCTAssertTrue(ExerciseLogging.isValid(input(
            name: "Farmer's Carry", weightKG: 24, distanceMeters: 20
        )))
        XCTAssertFalse(ExerciseLogging.isValid(input(
            name: "Farmer's Carry", weightKG: 24, durationSeconds: 30, distanceMeters: 20
        )))
        XCTAssertFalse(ExerciseLogging.isValid(input(
            name: "Burpee", rounds: 8, workSeconds: 30
        )))
        XCTAssertTrue(ExerciseLogging.isValid(input(
            name: "Burpee", rounds: 8, workSeconds: 30, recoverySeconds: 20
        )))
        XCTAssertFalse(ExerciseLogging.isValid(input(name: "Sun Salutation A")))
    }

    func testDeferredCircuitCanResolveOnlyThroughAnExplicitSkip() {
        let unsupported = input(
            name: "Sun Salutation A", weightKG: 20, reps: 8,
            durationSeconds: 30, distanceMeters: 20, rounds: 2,
            workSeconds: 30, recoverySeconds: 15
        )
        XCTAssertFalse(ExerciseLogging.isResolved(unsupported))

        let skipped = ExerciseLogging.resolvingAsSkipped(unsupported)
        XCTAssertTrue(ExerciseLogging.isResolved(skipped))
        XCTAssertTrue(skipped.skipped)
        XCTAssertNil(skipped.weightKG)
        XCTAssertNil(skipped.reps)
        XCTAssertNil(skipped.durationSeconds)
        XCTAssertNil(skipped.distanceMeters)
        XCTAssertNil(skipped.rounds)
        XCTAssertNil(skipped.workSeconds)
        XCTAssertNil(skipped.recoverySeconds)
    }

    func testNormalizationMakesBodyweightExplicitAndSkippedFactsEmpty() {
        let bodyweight = ExerciseLogging.normalized(input(
            name: "Pull-Up", reps: 8
        ))
        XCTAssertEqual(bodyweight.weightKG, 0)
        XCTAssertNil(bodyweight.rir)

        let skipped = ExerciseLogging.normalized(input(
            name: "Pull-Up", weightKG: -20, reps: 8, durationSeconds: 30,
            distanceMeters: 20, rounds: 3, workSeconds: 30, recoverySeconds: 20,
            skipped: true
        ))
        XCTAssertNil(skipped.weightKG)
        XCTAssertNil(skipped.reps)
        XCTAssertNil(skipped.durationSeconds)
        XCTAssertNil(skipped.distanceMeters)
        XCTAssertNil(skipped.rounds)
        XCTAssertNil(skipped.workSeconds)
        XCTAssertNil(skipped.recoverySeconds)
    }

    func testSkippedSetClearsEveryTypedFact() {
        let input = WorkoutSetInput(
            exerciseID: nil,
            exerciseName: "Farmer's Carry",
            setNumber: 1,
            weightKG: 24,
            reps: 10,
            rir: 2,
            movementID: "farmers_carry",
            durationSeconds: 30,
            distanceMeters: 20,
            rounds: 4,
            workSeconds: 30,
            recoverySeconds: 20,
            skipped: true
        ).normalizedForPersistence()

        XCTAssertNil(input.weightKG)
        XCTAssertNil(input.reps)
        XCTAssertNil(input.rir)
        XCTAssertNil(input.durationSeconds)
        XCTAssertNil(input.distanceMeters)
        XCTAssertNil(input.rounds)
        XCTAssertNil(input.workSeconds)
        XCTAssertNil(input.recoverySeconds)
        XCTAssertEqual(input.movementID, "farmers_carry")
    }

    private func log(
        userID: UUID = UUID(),
        sessionID: UUID = UUID(),
        exerciseName: String = "Test",
        movementID: String? = nil,
        weightKG: Double? = nil,
        reps: Int? = nil,
        rir: Int? = 2,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rounds: Int? = nil,
        workSeconds: Int? = nil,
        recoverySeconds: Int? = nil
    ) -> WorkoutLog {
        WorkoutLog(
            id: UUID(),
            userID: userID,
            sessionID: sessionID,
            exerciseID: nil,
            exerciseName: exerciseName,
            setNumber: 1,
            weightKG: weightKG,
            reps: reps,
            rir: rir,
            movementID: movementID,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            rounds: rounds,
            workSeconds: workSeconds,
            recoverySeconds: recoverySeconds,
            skipped: false,
            overrideFlag: false,
            createdAt: "2026-08-23T08:00:00Z"
        )
    }

    private func input(
        name: String,
        weightKG: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rounds: Int? = nil,
        workSeconds: Int? = nil,
        recoverySeconds: Int? = nil,
        skipped: Bool = false
    ) -> WorkoutSetInput {
        WorkoutSetInput(
            exerciseID: nil,
            exerciseName: name,
            setNumber: 1,
            weightKG: weightKG,
            reps: reps,
            rir: nil,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            rounds: rounds,
            workSeconds: workSeconds,
            recoverySeconds: recoverySeconds,
            skipped: skipped
        )
    }

    private func session(id: UUID, userID: UUID, date: String) -> WorkoutSession {
        WorkoutSession(
            id: id,
            userID: userID,
            date: date,
            programDayID: UUID(),
            isLite: false,
            isDeload: false,
            isEventRecovery: false,
            completed: true,
            qualityScore: 1,
            startedAt: nil,
            completedAt: nil,
            notes: ""
        )
    }
}
