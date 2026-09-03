/*
 * Golden parity for the HealthImport merge policy against
 * src/lib/healthImport.ts (Tools/generate-health-import-fixtures.mts).
 *
 * The policy is the whole point: an import is a positive signal only, a
 * manual entry always wins, water rises but never falls, and re-importing
 * does not duplicate work already recorded.
 */
import XCTest
import HealthKit
@testable import APEX

private struct HealthFixture: Decodable {
    let user_id: UUID
    let existing: Existing
    let parsed: ParsedRows
    let expected: Expected
}

private struct Existing: Decodable {
    let daily_logs: [DailyLogRow]
    let metrics: [MetricRow]
    let activities: [ActivityRow]
}

private struct DailyLogRow: Decodable {
    let id: UUID?; let date: String
    let kcal: Int?; let protein_g: Int?; let fat_g: Int?; let carbs_g: Int?
    let water_l: Double
}

private struct MetricRow: Decodable {
    let id: UUID?; let date: String
    let weight_kg: Double?; let vo2max: Double?; let resting_hr: Double?
}

private struct ActivityRow: Decodable {
    let date: String; let kind: String; let activity: String
    let duration_min: Int; let source: String
}

private struct ParsedRows: Decodable {
    let nutrition: [NutritionRow]
    let water: [WaterRow]
    let weight: [ValueRow]
    let vo2max: [ValueRow]
    let resting_hr: [ValueRow]
    let workouts: [WorkoutRow]
}

private struct NutritionRow: Decodable { let date: String; let kcal: Double; let protein: Double; let fat: Double; let carbs: Double }
private struct WaterRow: Decodable { let date: String; let litres: Double }
private struct ValueRow: Decodable { let date: String; let kg: Double?; let value: Double? }
private struct WorkoutRow: Decodable { let date: String; let activity: String; let kind: String; let durationMin: Int; let source: String }

private struct Expected: Decodable {
    let daily_logs: [DailyLogRow]
    let metrics: [MetricRow]
    let activities: [ActivityRow]
    let result: ResultRow
}

private struct ResultRow: Decodable {
    let dailyLogsTouched: Int
    let metricsTouched: Int
    let workoutsAdded: Int
    let latestWeight: Double?
    let latestVo2max: Double?
    let dateRange: [String]?
}

final class HealthImportParityTests: XCTestCase {
    private static let fixture: HealthFixture = {
        guard let url = Bundle(for: HealthImportParityTests.self)
            .url(forResource: "health-import-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("health-import-parity.json missing from the test bundle")
        }
        return try! JSONDecoder().decode(HealthFixture.self, from: data)
    }()

    private func built() -> HealthImport.Rows {
        let fixture = Self.fixture
        var parsed = HealthImport.Parsed()
        for row in fixture.parsed.nutrition {
            parsed.nutrition[row.date] = .init(kcal: row.kcal, protein: row.protein, fat: row.fat, carbs: row.carbs)
        }
        for row in fixture.parsed.water { parsed.water[row.date] = row.litres }
        for row in fixture.parsed.weight { parsed.weight[row.date] = row.kg ?? row.value ?? 0 }
        for row in fixture.parsed.vo2max { parsed.vo2Max[row.date] = row.value ?? row.kg ?? 0 }
        for row in fixture.parsed.resting_hr { parsed.restingHeartRate[row.date] = row.value ?? row.kg ?? 0 }
        parsed.workouts = fixture.parsed.workouts.map {
            .init(date: $0.date, activity: $0.activity, kind: $0.kind, durationMinutes: $0.durationMin, source: $0.source)
        }

        let logs = fixture.existing.daily_logs.map { row in
            DailyLog(
                id: row.id ?? UUID(), userID: fixture.user_id, date: row.date,
                kcal: row.kcal, proteinG: row.protein_g, fatG: row.fat_g, carbsG: row.carbs_g,
                waterL: row.water_l, estimatedTDEE: nil, computedPAL: nil,
                activityMode: "quick", weightKG: nil
            )
        }
        let metrics = fixture.existing.metrics.map { row in
            HealthMetric(
                id: row.id ?? UUID(), userID: fixture.user_id, date: row.date,
                weightKG: row.weight_kg, vo2Max: row.vo2max, restingHeartRate: row.resting_hr
            )
        }
        let activities = fixture.existing.activities.map { row in
            ImportedActivity(
                id: UUID(), userID: fixture.user_id, date: row.date, kind: row.kind,
                activity: row.activity, durationMinutes: row.duration_min, source: row.source
            )
        }
        return HealthImport.buildRows(
            parsed: parsed, userID: fixture.user_id,
            dailyLogs: logs, metrics: metrics, activities: activities
        )
    }

    private func linkingSession(
        id: UUID = UUID(),
        ownerID: UUID,
        startedAt: String = "2026-08-29T10:00:00.000Z",
        completedAt: String = "2026-08-29T11:00:00.000Z"
    ) -> WorkoutSession {
        WorkoutSession(
            id: id, userID: ownerID, date: "2026-08-29", programDayID: UUID(),
            isLite: false, isDeload: false, isEventRecovery: false,
            completed: true, qualityScore: 1, startedAt: startedAt,
            completedAt: completedAt, notes: "Completed in APEX"
        )
    }

    private func linkingActivity(
        id: UUID = UUID(),
        ownerID: UUID,
        startedAt: String = "2026-08-29T09:55:00.000Z",
        endedAt: String = "2026-08-29T10:55:00.000Z",
        sourceBundleIdentifier: String = "com.apple.health",
        linkedSessionID: UUID? = nil,
        hiddenAt: String? = nil
    ) -> ImportedActivity {
        ImportedActivity(
            id: id, userID: ownerID, date: "2026-08-29", kind: "strength",
            activity: "Traditional Strength Training", durationMinutes: 60,
            source: "Constantin’s Apple Watch", healthKitWorkoutID: UUID(),
            startedAt: startedAt, endedAt: endedAt,
            workoutNameKey: "health.workout.traditional_strength_training",
            sourceBundleIdentifier: sourceBundleIdentifier,
            apexWorkoutSessionID: linkedSessionID, hiddenAt: hiddenAt
        )
    }

    func testOneOverlappingWearableWorkoutLinksAtTheInclusiveFiveMinuteBoundary() {
        let ownerID = UUID()
        let session = linkingSession(ownerID: ownerID)
        let boundary = linkingActivity(ownerID: ownerID)

        let links = WearableWorkoutLinking.automaticLinks(
            sessions: [session], activities: [boundary], ownerID: ownerID
        )

        XCTAssertEqual(links.map(\.id), [boundary.id])
        XCTAssertEqual(links.first?.apexWorkoutSessionID, session.id)
        let endedBeforeStart = linkingActivity(
            ownerID: ownerID,
            startedAt: "2026-08-29T09:50:00.000Z",
            endedAt: "2026-08-29T09:59:59.000Z"
        )
        XCTAssertTrue(WearableWorkoutLinking.automaticLinks(
            sessions: [session], activities: [endedBeforeStart], ownerID: ownerID
        ).isEmpty)
    }

    func testAutomaticWearableAssociationRefusesAmbiguousActivitiesAndSessions() {
        let ownerID = UUID()
        let firstSession = linkingSession(ownerID: ownerID)
        let firstActivity = linkingActivity(ownerID: ownerID, startedAt: "2026-08-29T09:58:00.000Z")
        let secondActivity = linkingActivity(ownerID: ownerID, startedAt: "2026-08-29T10:02:00.000Z")
        XCTAssertTrue(WearableWorkoutLinking.automaticLinks(
            sessions: [firstSession], activities: [firstActivity, secondActivity], ownerID: ownerID
        ).isEmpty)

        let secondSession = linkingSession(
            ownerID: ownerID, startedAt: "2026-08-29T10:01:00.000Z"
        )
        XCTAssertTrue(WearableWorkoutLinking.automaticLinks(
            sessions: [firstSession, secondSession], activities: [secondActivity], ownerID: ownerID
        ).isEmpty)
    }

    func testManualWearableChoicesAreOwnerDayScopedExternalAndNewestFirst() {
        let ownerID = UUID()
        let session = linkingSession(ownerID: ownerID)
        let older = linkingActivity(ownerID: ownerID, startedAt: "2026-08-29T07:00:00.000Z")
        let newer = linkingActivity(ownerID: ownerID, startedAt: "2026-08-29T12:00:00.000Z")
        let hidden = linkingActivity(ownerID: ownerID, hiddenAt: "2026-08-29T12:30:00.000Z")
        let mirror = linkingActivity(
            ownerID: ownerID, sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp"
        )
        let linked = linkingActivity(ownerID: ownerID, linkedSessionID: UUID())
        let foreign = linkingActivity(ownerID: UUID())

        let candidates = WearableWorkoutLinking.candidatesForDay(
            activities: [older, newer, hidden, mirror, linked, foreign],
            ownerID: ownerID,
            date: "2026-08-29"
        )

        XCTAssertEqual(candidates.map(\.id), [newer.id, older.id])
        XCTAssertEqual(
            WearableWorkoutLinking.explicitLink(newer, to: session)?.apexWorkoutSessionID,
            session.id
        )
        XCTAssertNil(WearableWorkoutLinking.explicitLink(foreign, to: session))
    }

    func testHealthKitRefreshPreservesAnExternalWearableLink() {
        let ownerID = UUID()
        let sessionID = UUID()
        let workout = healthWorkout(
            id: "20000000-0000-0000-0000-000000000321",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.traditional_strength_training",
            sourceBundleIdentifier: "com.apple.health"
        )
        let canonical = ExternalWorkoutImport.importedActivity(from: workout, ownerID: ownerID)
        let linked = ImportedActivity(
            id: canonical.id, userID: canonical.userID, date: canonical.date,
            kind: canonical.kind, activity: canonical.activity,
            durationMinutes: max(1, canonical.durationMinutes - 1), source: canonical.source,
            healthKitWorkoutID: canonical.healthKitWorkoutID,
            startedAt: canonical.startedAt, endedAt: canonical.endedAt,
            workoutNameKey: canonical.workoutNameKey,
            distanceKM: canonical.distanceKM,
            activeEnergyKcal: canonical.activeEnergyKcal,
            sourceBundleIdentifier: canonical.sourceBundleIdentifier,
            activityTypeRaw: canonical.activityTypeRaw,
            apexWorkoutSessionID: sessionID
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [workout], deletedWorkoutIDs: []),
            existing: [linked], apexSessions: [], ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertEqual(result.upserts.first?.apexWorkoutSessionID, sessionID)
        XCTAssertFalse(ExternalWorkoutImport.isAPEXMirror(linked, apexSessions: [
            .init(id: sessionID, startedAt: workout.startedAt)
        ]))
    }

    func testExternalCompletionUsesTheViewedDayForReceiptAndWearableOwnership() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSession = try String(contentsOf: nativeRoot.appending(
            path: "APEX/App/AppSession.swift"
        ))
        let player = try String(contentsOf: nativeRoot.appending(
            path: "APEX/Features/Training/TrainingProgramView.swift"
        ))
        let compactSession = appSession.filter { !$0.isWhitespace }
        let compactPlayer = player.filter { !$0.isWhitespace }

        XCTAssertTrue(appSession.contains("completionDate: String? = nil"))
        XCTAssertTrue(appSession.contains(
            "let completedDate = completionDate ?? Date().apexDateKey"
        ))
        XCTAssertGreaterThanOrEqual(
            compactSession.components(separatedBy: "date:completedDate").count - 1,
            2,
            "both the workout receipt and its generated activity must use the viewed day"
        )
        XCTAssertTrue(compactSession.contains("isDeload(on:completedDate,"))
        XCTAssertTrue(appSession.contains("if wearableLinkRequest == .automatic,\n           let profile"))
        XCTAssertTrue(compactPlayer.contains(
            "wearableLinkRequest:linkRequest,completionDate:date,operation:operation"
        ))
    }

    func testDailyLogsMatchTheWeb() {
        let rows = built().dailyLogs.sorted { $0.date < $1.date }
        let expected = Self.fixture.expected.daily_logs
        XCTAssertEqual(rows.map(\.date), expected.map(\.date))
        for (row, want) in zip(rows, expected) {
            XCTAssertEqual(row.kcal, want.kcal, want.date)
            XCTAssertEqual(row.proteinG, want.protein_g, want.date)
            XCTAssertEqual(row.fatG, want.fat_g, want.date)
            XCTAssertEqual(row.carbsG, want.carbs_g, want.date)
            XCTAssertEqual(row.waterL, want.water_l, accuracy: 0.0001, want.date)
        }
    }

    func testMetricsAndActivitiesMatchTheWeb() {
        let rows = built()
        let metrics = rows.metrics.sorted { $0.date < $1.date }
        XCTAssertEqual(metrics.map(\.date), Self.fixture.expected.metrics.map(\.date))
        for (row, want) in zip(metrics, Self.fixture.expected.metrics) {
            XCTAssertEqual(row.weightKG ?? .nan, want.weight_kg ?? .nan, accuracy: 0.0001, want.date)
            XCTAssertEqual(row.vo2Max == nil, want.vo2max == nil, want.date)
            XCTAssertEqual(row.restingHeartRate == nil, want.resting_hr == nil, want.date)
        }
        let activities = rows.activities.sorted {
            $0.date == $1.date ? $0.activity < $1.activity : $0.date < $1.date
        }
        XCTAssertEqual(activities.map(\.activity), Self.fixture.expected.activities.map(\.activity))
        XCTAssertEqual(activities.map(\.durationMinutes), Self.fixture.expected.activities.map(\.duration_min))
    }

    func testResultMatchesTheWeb() {
        let result = built().result
        let want = Self.fixture.expected.result
        XCTAssertEqual(result.dailyLogsTouched, want.dailyLogsTouched)
        XCTAssertEqual(result.metricsTouched, want.metricsTouched)
        XCTAssertEqual(result.workoutsAdded, want.workoutsAdded)
        XCTAssertEqual(result.latestWeight ?? .nan, want.latestWeight ?? .nan, accuracy: 0.0001)
        XCTAssertEqual(result.latestVO2Max ?? .nan, want.latestVo2max ?? .nan, accuracy: 0.0001)
        XCTAssertEqual(result.dateRange, want.dateRange)
    }

    /// The rules stated in prose, asserted directly rather than only through
    /// the fixture, so a future change has to break them explicitly.
    func testAManualEntryAlwaysWins() {
        let rows = built().dailyLogs
        XCTAssertNil(
            rows.first { $0.date == "2026-08-10" },
            "a day already logged by hand must not be rewritten by an import"
        )
        let partial = rows.first { $0.date == "2026-08-11" }
        XCTAssertEqual(partial?.proteinG, 99, "an existing macro must survive the import")
        XCTAssertEqual(partial?.kcal, 2400, "an empty macro should be filled")
    }

    func testWaterRisesButNeverFalls() {
        let rows = built().dailyLogs
        XCTAssertNil(rows.first { $0.date == "2026-08-10" }, "2.5 L logged by hand must not fall to 1.2")
        XCTAssertEqual(rows.first { $0.date == "2026-08-11" }?.waterL, 2.25, "rounded to the quarter litre")
    }

    func testReimportingAddsNothingTwice() {
        let first = built()
        XCTAssertEqual(first.activities.count, 2, "the already-recorded session must be skipped")
        /* Feed the freshly added activities back in: nothing should be new. */
        var parsed = HealthImport.Parsed()
        parsed.workouts = Self.fixture.parsed.workouts.map {
            .init(date: $0.date, activity: $0.activity, kind: $0.kind, durationMinutes: $0.durationMin, source: $0.source)
        }
        let again = HealthImport.buildRows(
            parsed: parsed, userID: Self.fixture.user_id,
            dailyLogs: [], metrics: [],
            activities: first.activities + Self.fixture.existing.activities.map {
                ImportedActivity(
                    id: UUID(), userID: Self.fixture.user_id, date: $0.date, kind: $0.kind,
                    activity: $0.activity, durationMinutes: $0.duration_min, source: $0.source
                )
            }
        )
        XCTAssertEqual(again.activities.count, 0, "a second import must add nothing")
    }

    func testShortAndUnmappedWorkoutsAreRejectedByTheSharedRules() {
        XCTAssertEqual(HealthImport.minimumWorkoutMinutes, 8)
        XCTAssertEqual(HealthImport.activityKind["Running"], "endurance")
        XCTAssertEqual(HealthImport.activityKind["Yoga"], "mobility")
        XCTAssertNil(HealthImport.activityKind["Curling"], "an unmapped type is skipped, not guessed")
    }

    func testHealthKitWorkoutImportHandlesHistoricalThenIncrementalResults() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let historical = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.running"
        )
        let first = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [historical], deletedWorkoutIDs: []),
            existing: [],
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )
        XCTAssertEqual(first.upserts.map(\.healthKitWorkoutID), [historical.id])

        let current = first.upserts
        let newWorkout = healthWorkout(
            id: "20000000-0000-0000-0000-000000000002",
            startedAt: Date(timeIntervalSince1970: 1_777_086_400),
            nameKey: "health.workout.traditional_strength_training"
        )
        let incremental = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [newWorkout], deletedWorkoutIDs: []),
            existing: current,
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )
        XCTAssertEqual(incremental.upserts.map(\.healthKitWorkoutID), [newWorkout.id])
    }

    func testLateAPEXSessionRemovesAnAlreadyImportedWatchMirrorWithoutANewHealthKitDelta() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let startedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let metadataMirror = ExternalWorkoutImport.importedActivity(
            from: healthWorkout(
                id: "20000000-0000-0000-0000-000000000001",
                startedAt: startedAt.addingTimeInterval(-3_600),
                nameKey: "health.workout.running",
                sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp",
                apexSessionID: sessionID
            ),
            ownerID: ownerID
        )
        let timeMatchedMirror = ExternalWorkoutImport.importedActivity(
            from: healthWorkout(
                id: "20000000-0000-0000-0000-000000000002",
                startedAt: startedAt.addingTimeInterval(20),
                nameKey: "health.workout.running",
                sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp"
            ),
            ownerID: ownerID
        )
        let genuineExternal = ExternalWorkoutImport.importedActivity(
            from: healthWorkout(
                id: "20000000-0000-0000-0000-000000000003",
                startedAt: startedAt,
                nameKey: "health.workout.running"
            ),
            ownerID: ownerID
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [], deletedWorkoutIDs: []),
            existing: [genuineExternal, timeMatchedMirror, metadataMirror],
            apexSessions: [.init(id: sessionID, startedAt: startedAt)],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertTrue(result.upserts.isEmpty)
        XCTAssertEqual(
            Set(result.importedActivityIDsToDelete),
            Set([metadataMirror.id, timeMatchedMirror.id])
        )
        XCTAssertFalse(result.importedActivityIDsToDelete.contains(genuineExternal.id))
    }

    func testHistoricalAPEXMirrorBeyondDashboardCapIsReconciledFromAccountScopedIdentityPages() async throws {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let otherOwnerID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let firstStart = Date(timeIntervalSince1970: 1_700_000_000)
        var ownerRows: [SupabaseService.WorkoutSessionIdentityRow] = []
        for index in (0 ..< 205).reversed() {
            ownerRows.append(SupabaseService.WorkoutSessionIdentityRow(
                id: UUID(uuidString: String(
                    format: "30000000-0000-0000-0000-%012llx",
                    Int64(index + 1)
                ))!,
                userID: ownerID,
                date: "2026-08-29",
                startedAt: firstStart.addingTimeInterval(Double(index) * 86_400).ISO8601Format(),
                completedAt: nil
            ))
        }
        let foreignRow = SupabaseService.WorkoutSessionIdentityRow(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000999")!,
            userID: otherOwnerID,
            date: "2026-08-29",
            startedAt: firstStart.ISO8601Format(),
            completedAt: nil
        )
        let remoteRows = ownerRows + [foreignRow]

        let identities = try await SupabaseService.collectWorkoutSessionIdentities(
            ownerID: ownerID,
            pageSize: 64
        ) { requestedOwnerID, range in
            XCTAssertEqual(requestedOwnerID, ownerID)
            let lower = min(range.lowerBound, remoteRows.count)
            let upper = min(lower + 37, range.upperBound + 1, remoteRows.count)
            return Array(remoteRows[lower ..< upper])
        }

        XCTAssertEqual(identities.count, ownerRows.count)
        XCTAssertFalse(identities.contains { $0.id == foreignRow.id })
        let oldestSession = try XCTUnwrap(identities.first { $0.id == ownerRows.last?.id })
        let mirror = ExternalWorkoutImport.importedActivity(
            from: healthWorkout(
                id: "20000000-0000-0000-0000-000000000099",
                startedAt: oldestSession.startedAt,
                nameKey: "health.workout.running",
                sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp",
                apexSessionID: oldestSession.id
            ),
            ownerID: ownerID
        )

        let reconciled = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [], deletedWorkoutIDs: []),
            existing: [mirror],
            apexSessions: identities,
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertEqual(reconciled.importedActivityIDsToDelete, [mirror.id])
        XCTAssertTrue(reconciled.upserts.isEmpty)

        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let serviceSource = try String(contentsOf: nativeRoot.appending(
            path: "APEX/Core/Networking/SupabaseService.swift"
        ))
        XCTAssertTrue(serviceSource.contains(
            ".select(\"id,user_id,date,started_at,completed_at\")"
        ))
        XCTAssertTrue(serviceSource.contains(".eq(\"user_id\", value: scopedOwnerID)"))
        XCTAssertTrue(serviceSource.contains(".eq(\"completed\", value: true)"))
        XCTAssertTrue(serviceSource.contains(".order(\"date\", ascending: false)"))
        XCTAssertTrue(serviceSource.contains(".order(\"id\", ascending: false)"))
    }

    func testHistoricalWorkoutPersistenceIsBoundedIntoOrderedBatches() {
        let rows = (0..<205).map { index in
            ImportedActivity(
                id: UUID(), userID: UUID(), date: "2026-08-29", kind: "endurance",
                activity: "Running \(index)", durationMinutes: 30, source: "Apple Health"
            )
        }

        let batches = ExternalWorkoutImport.persistenceBatches(rows)

        XCTAssertEqual(batches.map(\.count), [100, 100, 5])
        XCTAssertEqual(batches.flatMap { $0 }.map(\.id), rows.map(\.id))
    }

    func testWorkoutMetricAuthorizationCoversEverySupportedDistanceQuantity() {
        let identifiers = Set(HealthWorkoutMetrics.distanceIdentifiers)
        XCTAssertTrue(identifiers.isSuperset(of: [
            .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
            .distanceWheelchair, .distanceDownhillSnowSports,
        ]))
        if #available(iOS 18.0, watchOS 11.0, *) {
            XCTAssertTrue(identifiers.isSuperset(of: [
                .distanceCrossCountrySkiing, .distancePaddleSports,
                .distanceRowing, .distanceSkatingSports,
            ]))
        }
    }

    func testHealthKitWorkoutImportDeduplicatesStableUUIDAndAPEXMetadata() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let apexSessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let external = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.high_intensity_interval_training"
        )
        let apexMirror = healthWorkout(
            id: "20000000-0000-0000-0000-000000000002",
            startedAt: Date(timeIntervalSince1970: 1_777_000_100),
            nameKey: "health.workout.high_intensity_interval_training",
            sourceBundleIdentifier: "ch.apexperformance.APEX",
            apexSessionID: apexSessionID
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [external, external, apexMirror], deletedWorkoutIDs: []),
            existing: [],
            apexSessions: [.init(id: apexSessionID, startedAt: apexMirror.startedAt)],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertEqual(result.upserts.count, 1)
        XCTAssertEqual(result.upserts.first?.healthKitWorkoutID, external.id)
    }

    func testDuplicateExistingHealthKitRowsCollapseToOneCanonicalReceipt() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let workout = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.running"
        )
        let canonical = ExternalWorkoutImport.importedActivity(from: workout, ownerID: ownerID)
        let duplicate = ImportedActivity(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            userID: ownerID,
            date: canonical.date,
            kind: canonical.kind,
            activity: canonical.activity,
            durationMinutes: canonical.durationMinutes,
            source: canonical.source,
            healthKitWorkoutID: workout.id,
            startedAt: canonical.startedAt,
            endedAt: canonical.endedAt,
            workoutNameKey: canonical.workoutNameKey,
            distanceKM: canonical.distanceKM,
            activeEnergyKcal: canonical.activeEnergyKcal,
            sourceBundleIdentifier: canonical.sourceBundleIdentifier,
            activityTypeRaw: canonical.activityTypeRaw,
            apexWorkoutSessionID: canonical.apexWorkoutSessionID,
            hiddenAt: "2026-08-29T12:00:00Z"
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [workout], deletedWorkoutIDs: []),
            existing: [canonical, duplicate],
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertEqual(result.upserts.count, 1)
        XCTAssertEqual(result.upserts.first?.id, canonical.id)
        XCTAssertEqual(result.upserts.first?.hiddenAt, duplicate.hiddenAt)
        XCTAssertEqual(result.importedActivityIDsToDelete, [duplicate.id])
    }

    func testAPEXAppAndWatchBundlePrefixesDeduplicateTimeMatchedMirrors() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let startedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let appMirror = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: startedAt,
            nameKey: "health.workout.running",
            sourceBundleIdentifier: "ch.apexperformance.APEX"
        )
        let watchMirror = healthWorkout(
            id: "20000000-0000-0000-0000-000000000002",
            startedAt: startedAt.addingTimeInterval(30),
            nameKey: "health.workout.running",
            sourceBundleIdentifier: "ch.apexperformance.APEX.watchkitapp"
        )
        let external = healthWorkout(
            id: "20000000-0000-0000-0000-000000000003",
            startedAt: startedAt.addingTimeInterval(60),
            nameKey: "health.workout.running",
            sourceBundleIdentifier: "com.apple.health"
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [appMirror, watchMirror, external], deletedWorkoutIDs: []),
            existing: [],
            apexSessions: [.init(id: sessionID, startedAt: startedAt)],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertEqual(result.upserts.map(\.healthKitWorkoutID), [external.id])
    }

    func testAPEXBundleDetectionDoesNotMatchALookalikePrefix() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let startedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let impostor = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: startedAt,
            nameKey: "health.workout.running",
            sourceBundleIdentifier: "ch.apexperformance.APEXImpostor"
        )
        let sessions = [ExternalWorkoutImport.APEXSessionIdentity(
            id: sessionID,
            startedAt: startedAt
        )]

        XCTAssertFalse(ExternalWorkoutImport.isAPEXMirror(
            impostor,
            apexSessions: sessions
        ))
        XCTAssertFalse(ExternalWorkoutImport.isAPEXMirror(
            ExternalWorkoutImport.importedActivity(from: impostor, ownerID: ownerID),
            apexSessions: sessions
        ))
    }

    func testLegacyHealthKitUUIDRowMigratesToAccountScopedReceipt() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let workout = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.running"
        )
        let legacy = ImportedActivity(
            id: workout.id,
            userID: ownerID,
            date: workout.date,
            kind: "endurance",
            activity: "Running",
            durationMinutes: workout.durationMinutes,
            source: "Apple Health"
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [workout], deletedWorkoutIDs: []),
            existing: [legacy],
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertEqual(result.upserts.count, 1)
        XCTAssertEqual(result.upserts.first?.healthKitWorkoutID, workout.id)
        XCTAssertNotEqual(result.upserts.first?.id, legacy.id)
        XCTAssertEqual(result.importedActivityIDsToDelete, [legacy.id])
    }

    func testLegacyHealthKitUUIDMigrationDoesNotDeleteAnotherAccountsRow() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let otherOwnerID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let workout = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.running"
        )
        let foreignLegacy = ImportedActivity(
            id: workout.id,
            userID: otherOwnerID,
            date: workout.date,
            kind: "endurance",
            activity: "Running",
            durationMinutes: workout.durationMinutes,
            source: "Apple Health"
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [workout], deletedWorkoutIDs: []),
            existing: [foreignLegacy],
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: []
        )

        XCTAssertEqual(result.upserts.count, 1)
        XCTAssertTrue(result.importedActivityIDsToDelete.isEmpty)
    }

    func testDeniedHealthKitWorkoutReadLeavesExistingAccountStateUntouched() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let existing = ExternalWorkoutImport.importedActivity(
            from: healthWorkout(
                id: "20000000-0000-0000-0000-000000000001",
                startedAt: Date(timeIntervalSince1970: 1_777_000_000),
                nameKey: "health.workout.walking"
            ),
            ownerID: ownerID
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: nil,
            existing: [existing],
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: [existing.healthKitWorkoutID!]
        )

        XCTAssertTrue(result.upserts.isEmpty)
        XCTAssertTrue(result.importedActivityIDsToDelete.isEmpty)
        XCTAssertTrue(result.activityLogIDsToDelete.isEmpty)
    }

    func testHealthKitWorkoutRowsAreAccountScopedAndPreserveMissingMetrics() {
        let firstOwner = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let workout = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.outdoor_run",
            distanceKM: nil,
            activeEnergyKcal: nil
        )

        let first = ExternalWorkoutImport.importedActivity(from: workout, ownerID: firstOwner)
        let second = ExternalWorkoutImport.importedActivity(from: workout, ownerID: secondOwner)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.userID, firstOwner)
        XCTAssertEqual(second.userID, secondOwner)
        XCTAssertNil(first.distanceKM)
        XCTAssertNil(first.activeEnergyKcal)
    }

    func testExternalWorkoutEnergyIsNeverAddedToActivityLogsTwice() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let workout = healthWorkout(
            id: "20000000-0000-0000-0000-000000000001",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            nameKey: "health.workout.running",
            activeEnergyKcal: 641
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [workout], deletedWorkoutIDs: []),
            existing: [],
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: [workout.id]
        )

        XCTAssertEqual(result.activityLogIDsToDelete, [workout.id])
        XCTAssertEqual(result.upserts.first?.activeEnergyKcal, 641)
    }

    func testDeletedHealthKitWorkoutRemovesOnlyItsAPEXImport() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let removedID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let retainedID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let removed = ExternalWorkoutImport.importedActivity(
            from: healthWorkout(id: removedID.uuidString, startedAt: .distantPast, nameKey: "health.workout.running"),
            ownerID: ownerID
        )
        let retained = ExternalWorkoutImport.importedActivity(
            from: healthWorkout(id: retainedID.uuidString, startedAt: .distantPast, nameKey: "health.workout.walking"),
            ownerID: ownerID
        )

        let result = ExternalWorkoutImport.reconcile(
            changeSet: .init(workouts: [], deletedWorkoutIDs: [removedID]),
            existing: [removed, retained],
            apexSessions: [],
            ownerID: ownerID,
            legacyActivityLogIDs: [removedID]
        )

        XCTAssertEqual(result.importedActivityIDsToDelete, [removed.id])
        XCTAssertEqual(result.activityLogIDsToDelete, [removedID])
        XCTAssertFalse(result.importedActivityIDsToDelete.contains(retained.id))
    }

    func testCompleteHealthKitWorkoutCatalogHasAuthoredNaturalNames() {
        let activityTypes: [HKWorkoutActivityType] = [
            .americanFootball, .archery, .australianFootball, .badminton, .baseball,
            .basketball, .bowling, .boxing, .climbing, .cricket, .crossTraining,
            .curling, .cycling, .dance, .danceInspiredTraining, .elliptical,
            .equestrianSports, .fencing, .fishing, .functionalStrengthTraining,
            .golf, .gymnastics, .handball, .hiking, .hockey, .hunting, .lacrosse,
            .martialArts, .mindAndBody, .mixedMetabolicCardioTraining, .paddleSports,
            .play, .preparationAndRecovery, .racquetball, .rowing, .rugby, .running,
            .sailing, .skatingSports, .snowSports, .soccer, .softball, .squash,
            .stairClimbing, .surfingSports, .swimming, .tableTennis, .tennis,
            .trackAndField, .traditionalStrengthTraining, .volleyball, .walking,
            .waterFitness, .waterPolo, .waterSports, .wrestling, .yoga, .barre,
            .coreTraining, .crossCountrySkiing, .downhillSkiing, .flexibility,
            .highIntensityIntervalTraining, .jumpRope, .kickboxing, .pilates,
            .snowboarding, .stairs, .stepTraining, .wheelchairWalkPace,
            .wheelchairRunPace, .taiChi, .mixedCardio, .handCycling, .discSports,
            .fitnessGaming, .cardioDance, .socialDance, .pickleball, .cooldown,
            .swimBikeRun, .transition, .underwaterDiving, .other,
        ]

        XCTAssertEqual(activityTypes.count, 84, "keep pace with every public HealthKit workout type")
        XCTAssertEqual(Set(activityTypes.map(\.rawValue)).count, activityTypes.count)
        for type in activityTypes {
            let identity = HealthWorkoutCatalog.identity(for: type)
            XCTAssertTrue(identity.nameKey.hasPrefix("health.workout."), "missing key for raw type \(type.rawValue)")
            XCTAssertFalse(identity.fallbackName.isEmpty, "missing name for raw type \(type.rawValue)")
            if type != .other {
                XCTAssertNotEqual(identity.nameKey, "health.workout.other", "type \(type.rawValue) fell through")
            }
        }

        XCTAssertEqual(
            HealthWorkoutCatalog.identity(for: .running, isIndoor: false).fallbackName,
            "Outdoor Run"
        )
        XCTAssertEqual(
            HealthWorkoutCatalog.identity(for: .traditionalStrengthTraining).fallbackName,
            "Traditional Strength Training"
        )
        XCTAssertEqual(
            HealthWorkoutCatalog.identity(for: .highIntensityIntervalTraining).fallbackName,
            "High Intensity Interval Training"
        )
    }

    private func healthWorkout(
        id: String,
        startedAt: Date,
        nameKey: String,
        sourceBundleIdentifier: String = "com.apple.health",
        apexSessionID: UUID? = nil,
        distanceKM: Double? = 5.2,
        activeEnergyKcal: Double? = 420
    ) -> HealthWorkoutSnapshot {
        HealthWorkoutSnapshot(
            id: UUID(uuidString: id)!,
            date: "2026-08-29",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            kind: "endurance",
            activityName: "Running",
            activityNameKey: nameKey,
            durationMinutes: 60,
            distanceKM: distanceKM,
            activeEnergyKcal: activeEnergyKcal,
            sourceName: "Constantin’s Apple Watch",
            sourceBundleIdentifier: sourceBundleIdentifier,
            activityTypeRaw: Int(HKWorkoutActivityType.running.rawValue),
            apexSessionID: apexSessionID
        )
    }
}

final class HealthAccountBoundarySourceTests: XCTestCase {
    private var nativeRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: nativeRoot.appending(path: relativePath))
    }

    private func compact(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func withoutWhitespace(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }

    func testHealthImportRequiresAnAccountScopedOptInAndOneLeaseAcrossEveryAwait() throws {
        let rawSession = try source("APEX/App/AppSession.swift")
        let session = compact(rawSession)
        let unspacedSession = withoutWhitespace(rawSession)

        XCTAssertTrue(session.contains("static func healthImportOptInKey(ownerID: UUID) -> String"))
        XCTAssertTrue(session.contains("apex.health-import.opt-in."))
        XCTAssertTrue(session.contains("func importHealthQuietly(operation: AccountOperationLease) async"))
        XCTAssertTrue(session.contains("healthImportIsEnabled(operation: operation)"))
        XCTAssertTrue(session.contains("func applyHealthSnapshot( _ snapshot: HealthSnapshot, operation: AccountOperationLease ) async"))
        XCTAssertTrue(session.contains("private func importHealthWorkoutChanges( operation: AccountOperationLease ) async"))
        XCTAssertTrue(session.contains("expectedAccountToken: operation.generation"))
        XCTAssertTrue(unspacedSession.contains(
            "startBackgroundMonitoring(ownerID:operation.ownerID){[weakself,operation]snapshotinawaitself?.applyHealthSnapshot(snapshot,operation:operation)"
        ))
        XCTAssertTrue(session.contains("HealthKitManager.shared.resetAccountBoundary()"))
    }

    func testAccessDenialInvalidatesInFlightHealthRefreshBeforeStoppingObservers() throws {
        let rawSession = try source("APEX/App/AppSession.swift")
        let session = withoutWhitespace(rawSession)
        let manager = withoutWhitespace(
            try source("APEX/Features/Health/HealthKitManager.swift")
        )

        let boundaryStart = try XCTUnwrap(
            session.range(of: "funcrouteToAccessRecoveryBoundary(forownerID:UUID)")
        )
        let boundaryEnd = try XCTUnwrap(
            session.range(
                of: "varinterfaceMode:",
                range: boundaryStart.upperBound..<session.endIndex
            )
        )
        let boundary = String(session[boundaryStart.lowerBound..<boundaryEnd.lowerBound])
        XCTAssertTrue(
            boundary.contains("HealthKitManager.shared.suspendPrivateWorkForAccessDenial()"),
            "access denial must revoke the HealthKit request generation, not merely stop current observers"
        )

        let suspensionStart = try XCTUnwrap(
            manager.range(of: "funcsuspendPrivateWorkForAccessDenial()")
        )
        let suspensionEnd = try XCTUnwrap(
            manager.range(
                of: "funcstopBackgroundMonitoring()",
                range: suspensionStart.upperBound..<manager.endIndex
            )
        )
        let suspension = String(
            manager[suspensionStart.lowerBound..<suspensionEnd.lowerBound]
        )
        XCTAssertTrue(suspension.contains("accountGeneration&+=1"))
        XCTAssertTrue(suspension.contains("stopBackgroundMonitoring()"))
    }

    func testDietaryWaterDeletionAnchorIsOwnerScopedAndCommittedAfterReconciliation() throws {
        let manager = withoutWhitespace(try source("APEX/Features/Health/HealthKitManager.swift"))
        let session = withoutWhitespace(try source("APEX/App/AppSession.swift"))

        XCTAssertTrue(manager.contains("dietaryWaterAnchorKey(ownerID:UUID)"))
        XCTAssertTrue(manager.contains("dietaryWaterDeletionChange(type:HKQuantityType,ownerID:UUID)"))
        XCTAssertFalse(manager.contains("defaults.set(anchorData,forKey:Self.dietaryWaterAnchorKey"))
        XCTAssertTrue(session.contains(
            "awaitreconcileHealthHydration(snapshot,operation:operation)guardaccountOperationIsCurrent(operation)else{return}ifletanchorData=snapshot.hydrationDeletionAnchorData{HealthKitManager.shared.commitDietaryWaterAnchor(anchorData,ownerID:ownerID)}"
        ))
    }

    func testEveryManualHealthImportCapturesTheLeaseBeforeStartingAsyncWork() throws {
        let expected: [(path: String, call: String)] = [
            ("APEX/Features/Settings/SettingsView.swift", "session.connectHealth(operation:operation)"),
            ("APEX/Features/Portal/SimpleHomeView.swift", "session.connectHealth(operation:operation)"),
            (
                "APEX/Features/Avatar/BaselineCalibrationSheet.swift",
                "session.connectHealthForBaselineCalibration(operation:operation)"
            ),
            ("APEX/Features/Onboarding/ConsentView.swift", "session.connectHealth(operation:operation)"),
        ]

        for contract in expected {
            let body = withoutWhitespace(try source(contract.path))
            let call = try XCTUnwrap(
                body.range(of: contract.call),
                "Missing account-bound Health action in \(contract.path)"
            )
            let lease = try XCTUnwrap(
                body.range(
                    of: "guardletoperation=session.accountOperationLease()else{return}",
                    options: .backwards,
                    range: body.startIndex..<call.lowerBound
                ),
                "Missing synchronously captured account lease in \(contract.path)"
            )
            let leaseOffset = body.distance(from: body.startIndex, to: lease.lowerBound)
            let callOffset = body.distance(from: body.startIndex, to: call.lowerBound)
            XCTAssertLessThan(
                leaseOffset,
                callOffset,
                "The lease must be captured before async Health work is scheduled in \(contract.path)"
            )
            if lease.lowerBound < call.lowerBound {
                XCTAssertTrue(
                    body[lease.lowerBound..<call.lowerBound].contains("Task{"),
                    "The already-captured lease must cross the Task boundary in \(contract.path)"
                )
            }
            XCTAssertFalse(
                body.contains("health.requestAccessAndImport()"),
                "Views must not bypass the account-scoped session Health gateway in \(contract.path)"
            )
        }
    }

    func testWaterReconnectAndFoodWaterWritesRequireTheInitiatingAccountsConsent() throws {
        let settings = withoutWhitespace(try source("APEX/Features/Settings/SettingsView.swift"))
        let session = withoutWhitespace(try source("APEX/App/AppSession.swift"))

        XCTAssertTrue(settings.contains(
            "guardletoperation=session.accountOperationLease()else{return}Task{awaitsession.reconnectHealthWaterAccess(operation:operation)}"
        ))
        XCTAssertFalse(settings.contains("health.reconnectWaterAccess()"))
        XCTAssertTrue(session.contains(
            "funcreconnectHealthWaterAccess(operation:AccountOperationLease)async"
        ))
        XCTAssertTrue(session.contains("tryenableHealthImport(operation:operation)"))
        XCTAssertTrue(session.contains("awaitHealthKitManager.shared.reconnectWaterAccess()"))
        XCTAssertTrue(session.contains(
            "ifhealthImportIsEnabled(operation:operation),HealthKitManager.shared.waterWriteState==.authorized"
        ))
    }

    func testNotificationConsentCapturesItsOwnerBeforeSchedulingAndRejectsStaleUI() throws {
        let consent = withoutWhitespace(try source("APEX/Features/Onboarding/ConsentView.swift"))
        let request = try XCTUnwrap(
            consent.range(of: "nudges.requestPermission(ownerID:operation.ownerID)")
        )
        let lease = try XCTUnwrap(
            consent.range(
                of: "guardletoperation=session.accountOperationLease()else{return}",
                options: .backwards,
                range: consent.startIndex..<request.lowerBound
            )
        )
        let preflightGuard = try XCTUnwrap(
            consent.range(
                of: "guardsession.accountOperationIsCurrent(operation)else{return}",
                options: .backwards,
                range: lease.upperBound..<request.lowerBound
            )
        )
        let staleGuard = try XCTUnwrap(
            consent.range(
                of: "guardsession.accountOperationIsCurrent(operation)else{return}",
                range: request.upperBound..<consent.endIndex
            )
        )

        XCTAssertLessThan(
            consent.distance(from: consent.startIndex, to: lease.lowerBound),
            consent.distance(from: consent.startIndex, to: request.lowerBound)
        )
        XCTAssertLessThan(
            consent.distance(from: consent.startIndex, to: preflightGuard.lowerBound),
            consent.distance(from: consent.startIndex, to: request.lowerBound)
        )
        XCTAssertGreaterThan(
            consent.distance(from: consent.startIndex, to: staleGuard.lowerBound),
            consent.distance(from: consent.startIndex, to: request.lowerBound)
        )
        XCTAssertFalse(consent.contains("session.profile?.userID"))
    }

    func testHealthAndWatchHydrationPersistenceUsesTheOriginalOperationLease() throws {
        let session = withoutWhitespace(try source("APEX/App/AppSession.swift"))
        let reconcileStart = try XCTUnwrap(session.range(of: "privatefuncreconcileHealthHydration"))
        let reconcileEnd = try XCTUnwrap(
            session.range(
                of: "privatefunchydrationHealthSampleBelongsToOwner",
                range: reconcileStart.upperBound..<session.endIndex
            )
        )
        let reconcile = String(session[reconcileStart.lowerBound..<reconcileEnd.lowerBound])
        let watchStart = try XCTUnwrap(
            session.range(of: "privatefunchandleHydrationMutation(_mutation:HydrationCompanionMutation,operation:AccountOperationLease)")
        )
        let watchEnd = try XCTUnwrap(
            session.range(
                of: "funcapplyHealthSnapshot",
                range: watchStart.upperBound..<session.endIndex
            )
        )
        let watchMutation = String(session[watchStart.lowerBound..<watchEnd.lowerBound])

        XCTAssertTrue(reconcile.contains(
            "materializeLegacyHydrationIfNeeded(ownerID:ownerID,date:date,operation:operation)"
        ))
        XCTAssertFalse(reconcile.contains("materializeLegacyHydrationIfNeeded(ownerID:ownerID,date:date)"))
        XCTAssertTrue(reconcile.contains(
            "mirrorHydrationAggregate(ownerID:ownerID,on:date,operation:operation)"
        ))
        XCTAssertTrue(watchMutation.contains(
            "mirrorHydrationAggregate(ownerID:ownerID,on:date,operation:operation)"
        ))
        XCTAssertTrue(watchMutation.contains(
            "saveHydrationPreferences(preferences.accountRow(ownerID:ownerID,existing:data.hydrationPreferences),operation:operation)"
        ))
    }

    func testWorkoutViewsKeepTheSameOwnerLeaseFromWatchStartThroughStop() throws {
        let player = withoutWhitespace(try source("APEX/Features/Training/TrainingProgramView.swift"))

        XCTAssertEqual(
            player.components(separatedBy: "@StateprivatevarwatchWorkoutOperation:AccountOperationLease?").count - 1,
            2,
            "Both tracked and follow-along workout surfaces need their own view-lifetime lease"
        )
        XCTAssertEqual(
            player.components(separatedBy: "@StateprivatevarwatchWorkoutStartTask:Task<Void,Never>?").count - 1,
            2,
            "Both workout surfaces must be able to cancel a Watch launch that is still awaiting handoff"
        )
        XCTAssertEqual(
            player.components(separatedBy: "@StateprivatevarwatchWorkoutLaunchID:UUID?").count - 1,
            2,
            "Both workout surfaces must retain the exact Watch launch they started"
        )
        XCTAssertEqual(
            player.components(separatedBy: "watchWorkoutOperation=operation").count - 1,
            2,
            "Each surface must retain the lease it captured before starting the Watch workout"
        )
        XCTAssertTrue(player.contains(
            "session.startWatchWorkout(day:day,exercises:exercises,launchID:launchID,operation:operation)"
        ))
        XCTAssertTrue(player.contains(
            "session.stopWatchWorkout(launchID:launchID,operation:operation)"
        ))
        XCTAssertGreaterThanOrEqual(
            player.components(separatedBy: "watchWorkoutStartTask?.cancel()").count - 1,
            4,
            "Disappear and completion paths must cancel a launch before issuing stop"
        )
        XCTAssertFalse(player.contains("session.stopWatchWorkout()"))

        let session = withoutWhitespace(try source("APEX/App/AppSession.swift"))
        let start = try XCTUnwrap(session.range(of: "funcstartWatchWorkout("))
        let end = try XCTUnwrap(
            session.range(of: "funcstopWatchWorkout(", range: start.upperBound..<session.endIndex)
        )
        let handoff = String(session[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(handoff.contains(
            "TrainingInduction.workoutOwnerID(in:data,day:day)==operation.ownerID"
        ))
        XCTAssertTrue(handoff.contains(
            "exercises.allSatisfy({$0.userID==operation.ownerID&&$0.programDayID==day.id})"
        ))
        let launchCommand = try XCTUnwrap(
            handoff.range(of: "letlaunchCommand=WatchWorkoutCommand.starting(ownerID:operation.ownerID,launchID:launchID)")
        )
        let healthStartCall = try XCTUnwrap(
            handoff.range(of: "letstarted=awaitHealthKitManager.shared.startWatchWorkout(kind)")
        )
        let successfulHandoff = try XCTUnwrap(
            handoff.range(of: "guardstartedelse{return}")
        )
        let commandSend = try XCTUnwrap(
            handoff.range(of: "hydrationConnectivity.send(launchCommand)")
        )
        XCTAssertLessThan(launchCommand.lowerBound, healthStartCall.lowerBound)
        XCTAssertGreaterThan(successfulHandoff.lowerBound, healthStartCall.lowerBound)
        XCTAssertGreaterThan(commandSend.lowerBound, healthStartCall.lowerBound)
        XCTAssertGreaterThan(commandSend.lowerBound, successfulHandoff.lowerBound)
        XCTAssertTrue(handoff.contains("letstarted=awaitHealthKitManager.shared.startWatchWorkout(kind)"))
        XCTAssertTrue(handoff.contains(
            "stopWatchWorkout(launchID:launchID,operation:operation)"
        ))

        let health = withoutWhitespace(try source("APEX/Features/Health/HealthKitManager.swift"))
        let healthStart = try XCTUnwrap(health.range(of: "funcstartWatchWorkout("))
        let healthEnd = try XCTUnwrap(
            health.range(of: "privatevarreadTypes", range: healthStart.upperBound..<health.endIndex)
        )
        let healthHandoff = String(health[healthStart.lowerBound..<healthEnd.lowerBound])
        XCTAssertTrue(healthHandoff.contains(
            "guardaccountGeneration==requestGenerationelse{returnresult.started}"
        ))
    }

    func testWatchLaunchAcceptanceIsDurableAndLaunchSpecific() throws {
        let watchApp = withoutWhitespace(try source("APEXWatch/APEXWaterWatchApp.swift"))
        let watchStore = withoutWhitespace(try source("APEXWatch/WatchHydrationStore.swift"))

        XCTAssertTrue(watchApp.contains(
            "ch.apexperformance.APEX.watch.workout-launch-ledger.v1"
        ))
        XCTAssertTrue(watchApp.contains(
            "JSONDecoder().decode(WatchWorkoutLaunchLedger.self,from:data)"
        ))
        XCTAssertTrue(watchApp.contains(
            "awaitWatchWorkoutSessionController.shared.receive(workoutConfiguration)"
        ))
        XCTAssertTrue(watchApp.contains(
            "funcreceive(_command:WatchWorkoutCommand)async"
        ))
        XCTAssertFalse(watchApp.contains(
            "funcreceive(_command:WatchWorkoutCommand,activeOwnerID:UUID?)"
        ))
        XCTAssertTrue(watchApp.contains(
            "launchLedger.permitsStart(launchID:intent.id,ownerID:intent.ownerID,activeOwnerID:activeOwnerID)"
        ))
        XCTAssertTrue(watchApp.contains("awaitstopSession(matching:launchID)"))
        XCTAssertTrue(watchStore.contains(
            "Task{@MainActor[weakself]inguardself!=nilelse{return}awaitWatchWorkoutSessionController.shared.receive(command)}"
        ))
        XCTAssertTrue(watchStore.contains("letdisconnectedOwnerID=activeOwnerID"))
        XCTAssertTrue(watchStore.contains(
            "WatchWorkoutSessionController.shared.updateActiveOwner(snapshot.ownerID,revision:snapshot.revision)"
        ))
        XCTAssertTrue(watchStore.contains(
            "WatchWorkoutSessionController.shared.disconnect(ownerID:disconnectedOwnerID,revision:revision)"
        ))
        XCTAssertTrue(watchApp.contains(
            "activeOwnerID=WatchWorkoutOwnerBoundary.ownerAfterDisconnect(activeOwnerID:activeOwnerID,disconnectedOwnerID:disconnectedOwnerID)"
        ))
        XCTAssertTrue(watchApp.contains(
            "launchLedger.revoke(ownerID:oldOwnerID,revision:boundaryRevision)"
        ))
        XCTAssertFalse(watchStore.contains(
            "guardself?.activeOwnerID==command.ownerID,command.action==.stop"
        ))
    }

    func testCancelledWatchHydrationMutationIsNotAcknowledgedAndGetsOneOwnerScopedRetry() throws {
        let session = withoutWhitespace(try source("APEX/App/AppSession.swift"))

        XCTAssertTrue(session.contains("finishHydrationMutation(_mutation:HydrationCompanionMutation,markProcessed:Bool)"))
        XCTAssertTrue(session.contains("guardmarkProcessedelse{return}"))
        XCTAssertTrue(session.contains("guard!Task.isCancelled,accountAccessAllowsPrivateWork(for:operation.ownerID),mutation.belongs(to:operation.ownerID),accountOperationIsCurrent(operation)else{"))
        XCTAssertTrue(session.contains("guard!Task.isCancelled,accountOperationIsCurrent(operation)else{return}publishHydrationState()markProcessed=true"))
        XCTAssertTrue(session.contains("enqueueHydrationMutationRetry(mutation)"))
        XCTAssertTrue(session.contains("retryPendingHydrationMutations(operation:operation)"))
        XCTAssertTrue(session.contains("attempts<1"))
        XCTAssertTrue(session.contains("mutation.ownerID==operation.ownerID"))
    }
}

final class WatchWorkoutLaunchLedgerTests: XCTestCase {
    private let ownerID = UUID(uuidString: "9a0b7ae1-d759-4c94-bcfd-1910bd10ddc0")!

    func testStopBeforeStartDiscardsTheMatchingLateConfigurationAfterRelaunch() throws {
        let launchID = UUID(uuidString: "23d75561-ef88-4f8f-8fe9-d6a8232334d3")!
        var ledger = WatchWorkoutLaunchLedger()

        XCTAssertEqual(
            ledger.receive(.stopping(ownerID: ownerID, launchID: launchID)),
            .none
        )
        let persisted = try JSONEncoder().encode(ledger)
        ledger = try JSONDecoder().decode(WatchWorkoutLaunchLedger.self, from: persisted)
        XCTAssertEqual(
            ledger.receive(.starting(ownerID: ownerID, launchID: launchID)),
            .none
        )
        XCTAssertEqual(
            ledger.resolveNextConfiguration(activeOwnerID: ownerID),
            .discard(launchID)
        )
        XCTAssertNil(ledger.active)
    }

    func testWrongOwnerStopCannotCancelAStartAwaitingAuthorization() {
        let launchID = UUID(uuidString: "de5107fd-1124-4a2b-98ca-61e247b9a0d2")!
        let otherOwnerID = UUID(uuidString: "a41d6198-d6a2-48cc-9c8b-4e0985dd284b")!
        var ledger = WatchWorkoutLaunchLedger()

        _ = ledger.receive(.starting(ownerID: ownerID, launchID: launchID))
        guard case .start = ledger.resolveNextConfiguration(activeOwnerID: ownerID) else {
            return XCTFail("The owner-qualified launch should be accepted")
        }
        XCTAssertEqual(
            ledger.receive(.stopping(ownerID: otherOwnerID, launchID: launchID)),
            .none
        )
        XCTAssertTrue(ledger.permitsStart(
            launchID: launchID,
            ownerID: ownerID,
            activeOwnerID: ownerID
        ))
    }

    func testDelayedDisconnectForOwnerADoesNotClearCanonicalOwnerB() {
        let otherOwnerID = UUID(uuidString: "a41d6198-d6a2-48cc-9c8b-4e0985dd284b")!

        XCTAssertEqual(
            WatchWorkoutOwnerBoundary.ownerAfterDisconnect(
                activeOwnerID: otherOwnerID,
                disconnectedOwnerID: ownerID
            ),
            otherOwnerID
        )
        XCTAssertNil(WatchWorkoutOwnerBoundary.ownerAfterDisconnect(
            activeOwnerID: ownerID,
            disconnectedOwnerID: ownerID
        ))
    }

    func testDelayedOldStopCannotEndANewerWorkoutForTheSameOwner() {
        let oldID = UUID(uuidString: "914c9d89-c817-49db-b8b5-655d997757bd")!
        let newID = UUID(uuidString: "3d542bbf-c860-47aa-8986-e4ad3076f799")!
        var ledger = WatchWorkoutLaunchLedger()

        _ = ledger.receive(.starting(ownerID: ownerID, launchID: oldID))
        guard case .start(let oldIntent) = ledger.resolveNextConfiguration(activeOwnerID: ownerID) else {
            return XCTFail("The first launch should start")
        }
        XCTAssertEqual(oldIntent.id, oldID)
        XCTAssertEqual(
            ledger.receive(.stopping(ownerID: ownerID, launchID: oldID)),
            .stopActive(oldID)
        )

        _ = ledger.receive(.starting(ownerID: ownerID, launchID: newID))
        guard case .start(let newIntent) = ledger.resolveNextConfiguration(activeOwnerID: ownerID) else {
            return XCTFail("The newer launch should start")
        }
        XCTAssertEqual(newIntent.id, newID)
        XCTAssertEqual(
            ledger.receive(.stopping(ownerID: ownerID, launchID: oldID)),
            .none
        )
        XCTAssertEqual(ledger.active?.id, newID)
    }

    func testDisconnectTombstoneSurvivesRelaunchAndRejectsAnOlderDelayedStart() throws {
        let launchID = UUID(uuidString: "6e18e2ef-5595-40b2-a61e-2f7cf38f73b3")!
        var ledger = WatchWorkoutLaunchLedger()
        XCTAssertEqual(
            ledger.disconnect(
                ownerID: ownerID,
                revision: "2026-09-02T07:05:00.000Z"
            ),
            .none
        )

        let persisted = try JSONEncoder().encode(ledger)
        var restored = try JSONDecoder().decode(WatchWorkoutLaunchLedger.self, from: persisted)
        _ = restored.receive(.starting(
            ownerID: ownerID,
            launchID: launchID,
            createdAt: "2026-09-02T07:04:59.000Z"
        ))

        XCTAssertEqual(
            restored.resolveNextConfiguration(activeOwnerID: ownerID),
            .discard(launchID)
        )
        XCTAssertNil(restored.active)
    }

    func testAStartCreatedAfterReconnectCanRunForTheSameOwner() {
        let launchID = UUID(uuidString: "7dd58d83-82f4-472f-b55b-c2dd8369611a")!
        var ledger = WatchWorkoutLaunchLedger()
        _ = ledger.disconnect(ownerID: ownerID, revision: "2026-09-02T07:05:00.000Z")
        _ = ledger.receive(.starting(
            ownerID: ownerID,
            launchID: launchID,
            createdAt: "2026-09-02T07:05:01.000Z"
        ))

        guard case .start(let intent) = ledger.resolveNextConfiguration(activeOwnerID: ownerID) else {
            return XCTFail("A post-reconnect launch should start")
        }
        XCTAssertEqual(intent.id, launchID)
        XCTAssertEqual(intent.ownerID, ownerID)
    }

    func testDisconnectStopsTheMatchingActiveLaunchButNotANewerOne() {
        let oldID = UUID(uuidString: "b8ac5bea-a6ea-43c8-93d4-f4de12609b80")!
        let newID = UUID(uuidString: "ef45752f-c567-46ae-a858-c57837827d79")!
        var ledger = WatchWorkoutLaunchLedger()

        _ = ledger.receive(.starting(
            ownerID: ownerID,
            launchID: oldID,
            createdAt: "2026-09-02T07:04:59.000Z"
        ))
        _ = ledger.resolveNextConfiguration(activeOwnerID: ownerID)
        XCTAssertEqual(
            ledger.disconnect(ownerID: ownerID, revision: "2026-09-02T07:05:00.000Z"),
            .stopActive(oldID)
        )

        _ = ledger.receive(.starting(
            ownerID: ownerID,
            launchID: newID,
            createdAt: "2026-09-02T07:05:01.000Z"
        ))
        _ = ledger.resolveNextConfiguration(activeOwnerID: ownerID)
        XCTAssertEqual(
            ledger.disconnect(ownerID: ownerID, revision: "2026-09-02T07:05:00.000Z"),
            .none
        )
        XCTAssertEqual(ledger.active?.id, newID)
    }

    func testCanonicalOwnerChangeRevokesOwnerAAndAllowsOwnerBToStart() {
        let otherOwnerID = UUID(uuidString: "a41d6198-d6a2-48cc-9c8b-4e0985dd284b")!
        let oldID = UUID(uuidString: "f49f77a1-a7db-4e24-8385-480f12c9a95c")!
        let newID = UUID(uuidString: "09648237-2f21-4ff1-9e33-01ba51af7225")!
        var ledger = WatchWorkoutLaunchLedger()

        _ = ledger.receive(.starting(
            ownerID: ownerID,
            launchID: oldID,
            createdAt: "2026-09-02T07:05:01.000Z"
        ))
        _ = ledger.resolveNextConfiguration(activeOwnerID: ownerID)
        XCTAssertEqual(
            ledger.revoke(ownerID: ownerID, revision: "2026-09-02T07:05:00.000Z"),
            .stopActive(oldID),
            "An accepted owner change revokes A even if A's launch timestamp is newer"
        )

        _ = ledger.receive(.starting(
            ownerID: otherOwnerID,
            launchID: newID,
            createdAt: "2026-09-02T07:05:02.000Z"
        ))
        guard case .start(let intent) = ledger.resolveNextConfiguration(
            activeOwnerID: otherOwnerID
        ) else {
            return XCTFail("Owner B must be able to start after A is revoked")
        }
        XCTAssertEqual(intent.id, newID)
        XCTAssertEqual(
            ledger.receive(.stopping(ownerID: ownerID, launchID: oldID)),
            .none
        )
        XCTAssertEqual(ledger.active?.id, newID)
    }
}

@MainActor
final class HealthObserverDeliveryTests: XCTestCase {
    func testCompletionRunsAfterTheSnapshotHasBeenDurablyConsumed() async {
        var events: [String] = []

        await HealthObserverDelivery.process(
            load: {
                events.append("read")
                return 42
            },
            consume: { value in
                events.append("persist-\(value)")
            },
            completion: {
                events.append("complete")
            }
        )

        XCTAssertEqual(events, ["read", "persist-42", "complete"])
    }

    func testCompletionStillRunsWhenTheHealthReadProducesNothing() async {
        var didComplete = false

        await HealthObserverDelivery.process(
            load: { Optional<Int>.none },
            consume: { _ in XCTFail("nil reads must not be consumed") },
            completion: { didComplete = true }
        )

        XCTAssertTrue(didComplete)
    }
}

private enum HealthReadTestError: Error {
    case protectedDataUnavailable
}

private func makeHealthTodayPlan(
    weightKG: @escaping @Sendable () async throws -> Double? = { nil },
    vo2Max: @escaping @Sendable () async throws -> Double? = { nil },
    restingHeartRate: @escaping @Sendable () async throws -> Double? = { nil },
    dietaryWater: @escaping @Sendable () async throws -> HealthWaterTotals = { .unavailable },
    steps: @escaping @Sendable () async throws -> Double? = { nil },
    activeEnergyKcal: @escaping @Sendable () async throws -> Double? = { nil },
    exerciseMinutes: @escaping @Sendable () async throws -> Double? = { nil },
    sleepDurationHours: @escaping @Sendable () async throws -> Double? = { nil },
    heartRateVariabilityMS: @escaping @Sendable () async throws -> Double? = { nil },
    workouts: @escaping @Sendable () async throws -> [HealthWorkoutSnapshot] = { [] }
) -> HealthTodayQueryPlan {
    HealthTodayQueryPlan(
        weightKG: weightKG,
        vo2Max: vo2Max,
        restingHeartRate: restingHeartRate,
        dietaryWater: dietaryWater,
        steps: steps,
        activeEnergyKcal: activeEnergyKcal,
        exerciseMinutes: exerciseMinutes,
        sleepDurationHours: sleepDurationHours,
        heartRateVariabilityMS: heartRateVariabilityMS,
        workouts: workouts
    )
}

private func unavailableHealthTodayPlan() -> HealthTodayQueryPlan {
    makeHealthTodayPlan(
        weightKG: { throw HealthReadTestError.protectedDataUnavailable },
        vo2Max: { throw HealthReadTestError.protectedDataUnavailable },
        restingHeartRate: { throw HealthReadTestError.protectedDataUnavailable },
        dietaryWater: { throw HealthReadTestError.protectedDataUnavailable },
        steps: { throw HealthReadTestError.protectedDataUnavailable },
        activeEnergyKcal: { throw HealthReadTestError.protectedDataUnavailable },
        exerciseMinutes: { throw HealthReadTestError.protectedDataUnavailable },
        sleepDurationHours: { throw HealthReadTestError.protectedDataUnavailable },
        heartRateVariabilityMS: { throw HealthReadTestError.protectedDataUnavailable },
        workouts: { throw HealthReadTestError.protectedDataUnavailable }
    )
}

final class HealthActivityEnergyResolutionTests: XCTestCase {
    func testActivitySummaryDayCarriesTheGregorianCalendarHealthKitRequires() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7_200)!
        let date = Date(timeIntervalSince1970: 1_777_000_000)

        let components = HealthActivitySummaryQueryDay.components(for: date, calendar: calendar)

        XCTAssertEqual(components.calendar?.identifier, .gregorian)
        XCTAssertEqual(components.calendar?.timeZone, calendar.timeZone)
        XCTAssertNotNil(components.era)
        XCTAssertNotNil(components.year)
        XCTAssertNotNil(components.month)
        XCTAssertNotNil(components.day)
        XCTAssertNotNil(
            HKQuery.predicateForActivitySummary(with: components),
            "HealthKit must accept the exact components before a launch refresh can query the activity ring"
        )
    }

    func testAppleFitnessActivitySummaryWinsWhenRawEnergySamplesLag() {
        XCTAssertEqual(
            HealthActivityEnergyResolver.resolve(
                activitySummaryKcal: 204,
                cumulativeSampleKcal: 22
            ),
            204
        )
    }

    func testAppleFitnessActivitySummaryAlsoWinsOverHigherOverlappingSamples() {
        XCTAssertEqual(
            HealthActivityEnergyResolver.resolve(
                activitySummaryKcal: 204,
                cumulativeSampleKcal: 231
            ),
            204
        )
    }

    func testPartialHealthRefreshPreservesLastReadableMetrics() {
        let existing = WearableActivityRecord(
            date: "2026-08-26",
            steps: 5_143,
            activeCalories: 204,
            exerciseMinutes: 31,
            source: "apple_health",
            updatedAt: "2026-08-26T17:30:00Z"
        )

        let merged = WearableActivityRecord.mergingHealthImport(
            date: "2026-08-26",
            existing: existing,
            steps: 5_221,
            activeEnergyKcal: nil,
            exerciseMinutes: nil,
            updatedAt: "2026-08-26T17:40:00Z"
        )

        XCTAssertEqual(merged?.steps, 5_221)
        XCTAssertEqual(merged?.activeCalories, 204)
        XCTAssertEqual(merged?.exerciseMinutes, 31)
    }

    func testCompleteHealthRefreshReplacesAllWearableFacts() {
        let existing = WearableActivityRecord(
            date: "2026-08-26",
            steps: 5_143,
            activeCalories: 204,
            exerciseMinutes: 31,
            source: "apple_health",
            updatedAt: "2026-08-26T17:30:00Z"
        )

        let merged = WearableActivityRecord.mergingHealthImport(
            date: "2026-08-26",
            existing: existing,
            steps: 6_000,
            activeEnergyKcal: 260,
            exerciseMinutes: 42,
            updatedAt: "2026-08-26T18:00:00Z"
        )

        XCTAssertEqual(merged?.steps, 6_000)
        XCTAssertEqual(merged?.activeCalories, 260)
        XCTAssertEqual(merged?.exerciseMinutes, 42)
    }
}

final class HealthTodayReadingsTests: XCTestCase {
    func testDeniedMetricDoesNotEraseReadableActivity() async throws {
        let snapshot = try await makeHealthTodayPlan(
            weightKG: { throw HealthReadTestError.protectedDataUnavailable },
            steps: { 8_432 },
            activeEnergyKcal: { 414 },
            exerciseMinutes: { 37 }
        ).snapshot(date: "2026-08-25")

        XCTAssertNil(snapshot.weightKG)
        XCTAssertEqual(snapshot.steps, 8_432)
        XCTAssertEqual(snapshot.activeEnergyKcal, 414)
        XCTAssertEqual(snapshot.exerciseMinutes, 37)
    }

    func testDeniedWaterDoesNotEraseReadableSleepOrWorkouts() async throws {
        let workout = HealthWorkoutSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000825")!,
            date: "2026-08-25",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: Date(timeIntervalSince1970: 1_777_003_600),
            kind: "endurance",
            activityName: "Running",
            durationMinutes: 60,
            distanceKM: 10,
            activeEnergyKcal: 620
        )
        let snapshot = try await makeHealthTodayPlan(
            dietaryWater: { throw HealthReadTestError.protectedDataUnavailable },
            sleepDurationHours: { 7.5 },
            workouts: { [workout] }
        ).snapshot(date: "2026-08-25")

        XCTAssertNil(snapshot.dietaryWaterL)
        XCTAssertNil(snapshot.importableDietaryWaterL)
        XCTAssertEqual(snapshot.sleepDurationHours, 7.5)
        XCTAssertEqual(snapshot.workouts, [workout])
        XCTAssertTrue(snapshot.hasImportableSignal)
    }

    func testEveryFailedQueryRejectsTheRefresh() async {
        do {
            _ = try await unavailableHealthTodayPlan().snapshot(date: "2026-08-25")
            XCTFail("A total HealthKit failure must not look like a successful empty day")
        } catch let error as HealthTodayReadError {
            XCTAssertEqual(error, .allQueriesUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuccessfulEmptyQueriesRemainAnHonestEmptySnapshot() async throws {
        let snapshot = try await makeHealthTodayPlan().snapshot(date: "2026-08-25")

        XCTAssertFalse(snapshot.hasImportableSignal)
        XCTAssertNil(snapshot.weightKG)
        XCTAssertNil(snapshot.vo2Max)
        XCTAssertNil(snapshot.restingHeartRate)
        XCTAssertNil(snapshot.dietaryWaterL)
        XCTAssertNil(snapshot.importableDietaryWaterL)
        XCTAssertNil(snapshot.steps)
        XCTAssertNil(snapshot.activeEnergyKcal)
        XCTAssertNil(snapshot.exerciseMinutes)
        XCTAssertNil(snapshot.sleepDurationHours)
        XCTAssertNil(snapshot.heartRateVariabilityMS)
        XCTAssertTrue(snapshot.workouts.isEmpty)
    }

    func testCancellationPropagatesInsteadOfPublishingAPartialSnapshot() async {
        let task = Task<HealthSnapshot, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await makeHealthTodayPlan(
                steps: { 8_432 },
                activeEnergyKcal: { 414 }
            ).snapshot(date: "2026-08-25")
        }

        do {
            _ = try await task.value
            XCTFail("Cancellation must stop the HealthKit refresh")
        } catch is CancellationError {
            // Expected: no partial snapshot escapes the cancelled lifecycle task.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportedWorkoutDashboardPaginationRetainsRowsBeyondLegacyCap() async throws {
        let remoteRows = Array(0 ..< 1_205)
        let serverPageCap = 137

        let loaded = try await SupabaseService.collectPaginatedRows(pageSize: 500) { range in
            let lower = min(range.lowerBound, remoteRows.count)
            let upper = min(lower + serverPageCap, range.upperBound + 1, remoteRows.count)
            return Array(remoteRows[lower ..< upper])
        }

        XCTAssertEqual(loaded, remoteRows)
    }
}
