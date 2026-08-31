import XCTest
@testable import APEX

final class FitnessBrainShadowValidationTests: XCTestCase {
    func testSharedParityScenarios() throws {
        let fixture: FitnessBrainShadowFixture = try decodeSharedFixture()

        for scenario in fixture.scenarios {
            XCTAssertEqual(
                FitnessBrainShadowValidator.compose(scenario.input),
                scenario.expected,
                "Scenario failed: \(scenario.name)"
            )
        }
    }

    func testObservationSerializationContainsBucketsAndCountsOnly() throws {
        let fixture: FitnessBrainShadowFixture = try decodeSharedFixture()
        let scenario = try XCTUnwrap(fixture.scenarios.first { $0.name.hasPrefix("supported and guided") })
        let data = try JSONEncoder().encode(FitnessBrainShadowValidator.compose(scenario.input))
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))

        for forbidden in [
            "user_id", "evidence_id", "receipt_id", "birthdate", "workout_name",
            "heart_rate", "vo2", "body_fat", "resting_metabolic_rate", "cardio-1",
            "upper-1", "sleep-1", "workout-1", "protein-1"
        ] {
            XCTAssertFalse(source.contains(forbidden), "Observation leaked \(forbidden)")
        }
    }

    func testEvidenceAdapterIsOwnerScopedAndIgnoresSupersededAndGenericFlexibility() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let otherOwnerID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let oldID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let newID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        let records = [
            evidence(id: oldID, ownerID: ownerID, metric: .cardioCapacityScore, value: 35),
            evidence(
                id: newID,
                ownerID: ownerID,
                metric: .cardioCapacityScore,
                value: 62,
                measuredAt: "2026-08-30T10:00:00Z",
                supersedesID: oldID
            ),
            evidence(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
                ownerID: ownerID,
                metric: .flexibilityScore,
                value: 88
            ),
            evidence(
                id: UUID(uuidString: "60000000-0000-0000-0000-000000000006")!,
                ownerID: otherOwnerID,
                metric: .upperBodyStrengthScore,
                value: 90
            )
        ]

        let inputs = FitnessBrainShadowValidator.buildCapacityInputs(
            records: records,
            ownerID: ownerID,
            asOf: "2026-08-31"
        )

        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs.first?.domain, .cardiorespiratory)
        XCTAssertEqual(inputs.first?.value, 62)
        XCTAssertEqual(inputs.first?.evidenceIDs, [newID.uuidString])
    }

    func testRolloutGateCannotActivateWithoutEveryReviewAndExplicitOwnerApproval() {
        let almostReady = FitnessBrainShadowRolloutEvidence(
            observationCount: 1_000,
            smallestSubgroupCount: 100,
            sufficientCoverageRate: 0.8,
            disagreementOutlierRate: 0.05,
            invariantViolationCount: 0,
            scientificReviewComplete: true,
            privacyReviewComplete: true,
            claimReviewComplete: true,
            ownerActivationApproved: false
        )

        XCTAssertEqual(
            FitnessBrainShadowValidator.evaluateRolloutGate(almostReady),
            .init(mode: .shadowOnly, blockers: ["owner_activation_required"])
        )

        var approved = almostReady
        approved.ownerActivationApproved = true
        XCTAssertEqual(
            FitnessBrainShadowValidator.evaluateRolloutGate(approved),
            .init(mode: .eligibleForControlledActivation, blockers: [])
        )
        XCTAssertEqual(FitnessBrainShadowValidator.presentationModelVersion, 1)
    }

    func testRuntimeObservationUsesLatestOwnedLegacySnapshot() {
        let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let otherOwnerID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let observation = FitnessBrainShadowValidator.runtimeObservation(
            ownerID: ownerID,
            observedOn: "2026-08-31",
            platform: .ios,
            profileKind: .standard,
            birthdate: "1988-06-20",
            sex: "female",
            legacySnapshots: [
                snapshot(ownerID: ownerID, date: "2026-08-29", overall: 31),
                snapshot(ownerID: otherOwnerID, date: "2026-08-31", overall: 99),
                snapshot(ownerID: ownerID, date: "2026-08-31", overall: 52),
                snapshot(ownerID: ownerID, date: "2026-09-01", overall: 88)
            ],
            evidence: []
        )

        XCTAssertEqual(observation.legacyOverallBand, .score40To59)
        XCTAssertEqual(observation.shadowOverallBand, .buildingBaseline)
        XCTAssertEqual(observation.ageBand, .age30To44)
        XCTAssertEqual(observation.sexGroup, .female)
    }

    func testRuntimeRPCPayloadStripsSubgroupAndPrivateFields() throws {
        let fixture: FitnessBrainShadowFixture = try decodeSharedFixture()
        let observation = FitnessBrainShadowValidator.compose(fixture.scenarios[1].input)
        let parameters = FitnessBrainShadowRPCParameters(observation: observation)
        let data = try JSONEncoder().encode(parameters)
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(parameters.outboxKey, "fitness-brain-shadow:2026-08-31:ios:2")
        for forbidden in ["\"profile_kind\"", "\"age_band\"", "\"sex_group\"", "\"user_id\"", "birthdate"] {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(forbidden))
        }
    }

    func testNativeOutboxCoalescesSameDayShadowRetries() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXShadowOutboxTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let ownerID = UUID()
        let store = OfflineStore(rootURL: rootURL)
        let fixture: FitnessBrainShadowFixture = try decodeSharedFixture()
        var first = FitnessBrainShadowValidator.compose(fixture.scenarios[1].input)
        let firstParameters = FitnessBrainShadowRPCParameters(observation: first)
        try await store.enqueueLatestFitnessBrainShadowObservation(
            .rpc("record_fitness_brain_shadow_observation", params: firstParameters),
            for: ownerID
        )

        first.shadowOverallBand = .strong
        let secondParameters = FitnessBrainShadowRPCParameters(observation: first)
        try await store.enqueueLatestFitnessBrainShadowObservation(
            .rpc("record_fitness_brain_shadow_observation", params: secondParameters),
            for: ownerID
        )

        let pending = try await store.pendingOperations(for: ownerID)
        XCTAssertEqual(pending.count, 1)
        let payload = try XCTUnwrap(pending.first?.payload)
        XCTAssertEqual(
            try JSONDecoder().decode(FitnessBrainShadowRPCParameters.self, from: payload).shadowOverallBand,
            .strong
        )
    }

    private func evidence(
        id: UUID,
        ownerID: UUID,
        metric: FitnessEvidenceMetric,
        value: Double,
        measuredAt: String = "2026-08-29T10:00:00Z",
        supersedesID: UUID? = nil
    ) -> FitnessEvidenceRecord {
        FitnessEvidenceRecord(
            id: id,
            userID: ownerID,
            metric: metric,
            value: value,
            unit: "score_0_100",
            source: .guidedAPEXFieldTest,
            protocol: "apex_test",
            device: nil,
            measuredAt: measuredAt,
            importedAt: measuredAt,
            confidence: .medium,
            metadata: [
                "lower_bound": .number(max(0, value - 10)),
                "upper_bound": .number(min(100, value + 10)),
                "coverage": .number(0.85)
            ],
            supersedesID: supersedesID,
            clientIdempotencyKey: "test:\(id.uuidString)"
        )
    }

    private func snapshot(ownerID: UUID, date: String, overall: Double) -> RPGSnapshot {
        RPGSnapshot(
            id: UUID(),
            userID: ownerID,
            date: date,
            overall: overall,
            health: 50,
            joint: 50,
            flexibility: 50,
            endurance: 50,
            strength: 50,
            strengthUpper: 50,
            strengthLower: 50
        )
    }

    private func decodeSharedFixture<T: Decodable>() throws -> T {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("tests/fixtures/fitness-brain-shadow-validation.json")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
