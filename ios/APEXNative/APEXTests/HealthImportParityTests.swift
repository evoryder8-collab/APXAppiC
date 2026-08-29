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
