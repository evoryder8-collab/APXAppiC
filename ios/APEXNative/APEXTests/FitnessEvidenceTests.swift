import XCTest
@testable import APEX

final class FitnessEvidenceTests: XCTestCase {
    func testSharedNormalizationScenarios() throws {
        let fixture: FitnessEvidenceNormalizationFixture = try decodeFixture()

        for scenario in fixture.scenarios {
            let result = FitnessEvidenceNormalizer.normalize(
                scenario.input,
                admission: scenario.admission,
                referenceNow: fixture.referenceNow,
                predecessor: scenario.predecessor
            )
            XCTAssertEqual(
                FitnessEvidenceNormalizer.summarize(result),
                scenario.expected,
                "Scenario failed: \(scenario.name)"
            )
        }
    }

    func testUserAdmissionNeverManufacturesTrustedEvidence() throws {
        let fixture: FitnessEvidenceNormalizationFixture = try decodeFixture()
        let trustedSources: Set<FitnessEvidenceSource> = [
            .indirectCalorimetry,
            .dexaMeasurement,
            .dexaDerivedEstimate,
            .clinicalMeasurement,
            .supportedDevice,
            .guidedAPEXFieldTest
        ]

        for scenario in fixture.scenarios where scenario.admission == .user {
            let result = FitnessEvidenceNormalizer.normalize(
                scenario.input,
                admission: scenario.admission,
                referenceNow: fixture.referenceNow,
                predecessor: scenario.predecessor
            )
            guard case .accepted(let evidence) = result else { continue }
            XCTAssertFalse(trustedSources.contains(evidence.source), "Scenario: \(scenario.name)")
            XCTAssertEqual(evidence.confidence, .low, "Scenario: \(scenario.name)")
        }
    }

    func testDatabaseRecordAndLegacyDashboardCacheDecode() throws {
        let recordData = Data("""
        {
          "id":"B32B9B53-67FA-4DA5-82CB-B572F739FAFA",
          "user_id":"FC4040CC-863F-444F-A568-AF71DAD83EC4",
          "metric":"vo2_max",
          "value":47.2,
          "unit":"ml_per_kg_min",
          "source":"supported_device",
          "protocol":null,
          "device":"Apple Watch",
          "measured_at":"2026-08-30T06:30:00Z",
          "imported_at":"2026-08-30T06:31:00Z",
          "confidence":"medium",
          "metadata":{"sample_uuid":"sample-1"},
          "supersedes_id":null,
          "client_idempotency_key":"healthkit-sample-1"
        }
        """.utf8)
        let record = try JSONDecoder().decode(FitnessEvidenceRecord.self, from: recordData)
        XCTAssertEqual(record.metric, .vo2Max)
        XCTAssertEqual(record.source, .supportedDevice)
        XCTAssertEqual(record.metadata["sample_uuid"], .string("sample-1"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedDashboard = try encoder.encode(DashboardData.empty)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedDashboard) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "fitnessEvidence")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(DashboardData.self, from: legacyData)
        XCTAssertTrue((legacy.fitnessEvidence ?? []).isEmpty)
    }

    func testRealtimeAndOfflineRPCContractsRemainAccountScoped() throws {
        let owner = UUID(uuidString: "FC4040CC-863F-444F-A568-AF71DAD83EC4")!
        let subscriptions = SupabaseService.realtimeSubscriptions(userID: owner)
        let evidence = try XCTUnwrap(subscriptions.first { $0.table == "fitness_evidence" })
        XCTAssertEqual(evidence.filterColumn, "user_id")
        XCTAssertEqual(evidence.filterValue, owner)

        let operation = try OfflineOperation.rpc(
            "record_user_fitness_evidence",
            params: ["p_client_idempotency_key": "baseline-flex-1"]
        )
        XCTAssertEqual(operation.kind, .rpc)
        XCTAssertEqual(operation.rpcFunction, "record_user_fitness_evidence")
        XCTAssertEqual(operation.table, "")
    }

    private func decodeFixture<T: Decodable>() throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "fitness-evidence-normalization",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

final class OnboardingBaselineTests: XCTestCase {
    func testSharedBroadBandScenarios() throws {
        let fixture: OnboardingBaselineFixture = try decodeOnboardingFixture()
        for scenario in fixture.scenarios {
            let result = OnboardingBaselineAssessment.evaluate(
                userID: fixture.userID,
                measuredAt: fixture.measuredAt,
                importedAt: fixture.importedAt,
                answers: scenario.input
            )
            XCTAssertEqual(
                OnboardingBaselineAssessment.summarize(result),
                scenario.expected,
                "Scenario failed: \(scenario.name)"
            )
        }
    }

    func testOnboardingEvidenceNeverClaimsPrecisionOrOverallFitness() throws {
        let fixture: OnboardingBaselineFixture = try decodeOnboardingFixture()
        let scenario = fixture.scenarios[1]
        let result = OnboardingBaselineAssessment.evaluate(
            userID: fixture.userID,
            measuredAt: fixture.measuredAt,
            importedAt: fixture.importedAt,
            answers: scenario.input
        )
        guard case .accepted(let evaluation) = result else {
            return XCTFail("Expected accepted onboarding baseline")
        }
        XCTAssertEqual(evaluation.bands.overallFitness, .buildingBaseline)
        XCTAssertEqual(OnboardingBaselineAssessment.movementDomains.count, 4)
        for draft in evaluation.evidence {
            XCTAssertEqual(draft.source, FitnessEvidenceSource.structuredSelfReport.rawValue)
            XCTAssertEqual(draft.requestedConfidence, FitnessEvidenceConfidence.low.rawValue)
            XCTAssertEqual(draft.metadata.objectValue?["display_precision"], .string("band_only"))
            XCTAssertTrue(draft.clientIdempotencyKey.hasPrefix("onboarding-v1:"))
        }
    }

    func testAnsweredSubmissionPersistsBodyAndMovementEvidenceDeterministically() throws {
        var input = TrainingInduction.Input(startDate: "2026-08-30")
        input.bodyBaseline = TrainingInduction.BodyBaseline(
            sex: "female",
            weightKG: 68,
            heightCM: 171,
            birthdate: "1990-02-03"
        )
        input.baselineAnswers = OnboardingBaselineAnswers(
            activityPattern: "mixed_day",
            cardiorespiratory: "developing",
            upperStrength: "capable",
            lowerStrength: "developing",
            mobility: "not_tested"
        )
        let submission = TrainingInduction.Submission.answered(input)
        XCTAssertEqual(submission.profileActivityLevel, .light)

        let owner = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = submission.fitnessEvidenceDrafts(
            userID: owner,
            importedAt: "2026-08-30T12:05:00Z"
        )
        let second = submission.fitnessEvidenceDrafts(
            userID: owner,
            importedAt: "2026-08-30T12:05:00Z"
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.metric), [
            "body_mass", "height", "cardio_capacity_score",
            "upper_body_strength_score", "lower_body_strength_score",
        ])
        for draft in first {
            guard case .accepted(let evidence) = FitnessEvidenceNormalizer.normalize(
                draft,
                admission: .user,
                referenceNow: "2026-08-30T12:05:00Z"
            ) else { return XCTFail("Onboarding generated invalid evidence") }
            XCTAssertEqual(evidence.confidence, .low)
            XCTAssertEqual(evidence.source, .structuredSelfReport)
        }
    }

    func testPlanMetadataRoundTripsAssessmentTimeAndWarningSymptoms() throws {
        let owner = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        var input = TrainingInduction.Input(startDate: "2026-08-30")
        input.availableMinutes = 45
        input.acuteSymptoms = true
        input.baselineAnswers = OnboardingBaselineAnswers(
            activityPattern: "on_feet",
            cardiorespiratory: "capable",
            upperStrength: "developing",
            lowerStrength: "capable",
            mobility: "not_tested"
        )
        let generated = TrainingInduction.generate(
            userID: owner,
            input: input,
            completedAt: "2026-08-30T12:05:00Z"
        )
        let restored = TrainingInduction.input(
            from: generated.induction,
            fallbackStartDate: input.startDate
        )
        XCTAssertEqual(restored.availableMinutes, 45)
        XCTAssertEqual(restored.acuteSymptoms, true)
        XCTAssertEqual(restored.baselineAnswers, input.baselineAnswers)
        XCTAssertEqual(TrainingInduction.assess(restored).caution, "clearance")
    }

    private func decodeOnboardingFixture<T: Decodable>() throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "onboarding-baseline",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

final class BaselineCalibrationTests: XCTestCase {
    func testCalibrationEvidenceChangesVisibleAvatarDomainsForItsOwner() throws {
        let owner = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        var dashboard = APEXDebugFixture.dashboard(userID: owner)
        var profile = try XCTUnwrap(dashboard.profile)
        profile.baselineDate = "2026-08-30"
        dashboard.profile = profile
        dashboard.programDays = []
        dashboard.exercises = []
        dashboard.workoutSessions = []
        dashboard.workoutLogs = []
        dashboard.dailyLogs = []
        dashboard.healthMetrics = []
        dashboard.importedActivities = []
        dashboard.fitnessEvidence = [
            calibrationEvidence(
                owner: owner,
                metric: .cardioCapacityScore,
                value: 77,
                importedAt: "2026-08-31T07:00:01Z"
            ),
            calibrationEvidence(owner: owner, metric: .cardioCapacityScore),
            calibrationEvidence(owner: owner, metric: .upperBodyStrengthScore),
            calibrationEvidence(owner: owner, metric: .lowerBodyStrengthScore),
            calibrationEvidence(owner: owner, metric: .flexibilityScore),
            calibrationEvidence(
                owner: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                metric: .cardioCapacityScore,
                value: 99
            ),
        ]

        let input = try XCTUnwrap(FitnessBrainService.engineInput(from: dashboard))
        let snapshot = try XCTUnwrap(
            FitnessBrainEngine.compute(input, throughDate: "2026-08-31").snapshots.last
        )
        var uncalibratedDashboard = dashboard
        uncalibratedDashboard.fitnessEvidence = []
        let uncalibratedInput = try XCTUnwrap(
            FitnessBrainService.engineInput(from: uncalibratedDashboard)
        )
        let uncalibrated = try XCTUnwrap(
            FitnessBrainEngine.compute(
                uncalibratedInput,
                throughDate: "2026-08-31"
            ).snapshots.last
        )

        XCTAssertEqual(snapshot.endurance, 36.7)
        XCTAssertEqual(snapshot.strengthUpper, 43.5)
        XCTAssertEqual(snapshot.strengthLower, 35.4)
        XCTAssertEqual(snapshot.flexibility, 34.5)
        XCTAssertEqual(snapshot.health, uncalibrated.health)
        XCTAssertEqual(snapshot.joint, uncalibrated.joint)
    }

    func testQuestionBankUsesTwelveDirectPromptsWithSpecificAnswers() {
        XCTAssertEqual(BaselineCalibrationQuestionBank.all.count, 12)
        XCTAssertEqual(Set(BaselineCalibrationQuestionBank.all.map(\.id)).count, 12)
        for question in BaselineCalibrationQuestionBank.all {
            XCTAssertEqual(question.options.count, 4, question.id)
            XCTAssertEqual(question.options.map(\.answer), [
                .foundation, .developing, .capable, .strong,
            ])
            XCTAssertEqual(Set(question.options.map(\.title)).count, 4, question.id)
            XCTAssertFalse(question.options.contains {
                ["Foundation", "Developing", "Capable", "Strong signal"].contains($0.title)
            }, question.id)
        }
    }

    func testContinueRequiresExplicitAnswerAndNotSureCounts() {
        let question = BaselineCalibrationQuestionBank.all[0]
        var draft = BaselineCalibrationDraft.empty
        draft.step = 1
        XCTAssertFalse(draft.isAnswered(question.id))
        draft.setAnswer(.notTested, for: question)
        XCTAssertTrue(draft.isAnswered(question.id))
    }

    func testDraftsResumeForTheirOwnerAndNeverCrossAccounts() throws {
        let suiteName = "BaselineCalibrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let owner = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let otherOwner = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        var answers = BaselineCalibrationAnswers.empty
        answers.cardiorespiratory[0] = BaselineCalibrationAnswer.capable.rawValue
        let draft = BaselineCalibrationDraft(
            step: 7,
            answers: answers,
            answeredQuestionIDs: Set(BaselineCalibrationQuestionBank.all.prefix(6).map(\.id))
        )

        BaselineCalibrationDraftStore.save(draft, userID: owner, defaults: defaults)
        XCTAssertEqual(BaselineCalibrationDraftStore.load(userID: owner, defaults: defaults), draft)
        XCTAssertNil(BaselineCalibrationDraftStore.load(userID: otherOwner, defaults: defaults))

        BaselineCalibrationDraftStore.clear(userID: otherOwner, defaults: defaults)
        XCTAssertEqual(BaselineCalibrationDraftStore.load(userID: owner, defaults: defaults), draft)
        BaselineCalibrationDraftStore.clear(userID: owner, defaults: defaults)
        XCTAssertNil(BaselineCalibrationDraftStore.load(userID: owner, defaults: defaults))
    }

    func testSharedCalibrationScenarios() throws {
        let fixture: BaselineCalibrationFixture = try decodeCalibrationFixture()
        for scenario in fixture.scenarios {
            let result = BaselineCalibrationAssessment.evaluate(
                userID: fixture.userID,
                measuredAt: fixture.measuredAt,
                importedAt: fixture.importedAt,
                answers: scenario.input
            )
            XCTAssertEqual(
                BaselineCalibrationAssessment.summarize(result),
                scenario.expected,
                "Scenario failed: \(scenario.name)"
            )
        }
    }

    func testCalibrationNeverClaimsOverallOrProgrammeAuthority() throws {
        let fixture: BaselineCalibrationFixture = try decodeCalibrationFixture()
        let result = BaselineCalibrationAssessment.evaluate(
            userID: fixture.userID,
            measuredAt: fixture.measuredAt,
            importedAt: fixture.importedAt,
            answers: fixture.scenarios[1].input
        )
        guard case .accepted(let evaluation) = result else {
            return XCTFail("Expected accepted calibration")
        }
        XCTAssertEqual(evaluation.bands.overallFitness, .buildingBaseline)
        XCTAssertFalse(evaluation.evidence.contains { $0.metric == "overall_fitness" })
        for evidence in evaluation.evidence {
            XCTAssertEqual(evidence.source, FitnessEvidenceSource.structuredSelfReport.rawValue)
            XCTAssertEqual(evidence.requestedConfidence, FitnessEvidenceConfidence.low.rawValue)
            XCTAssertEqual(evidence.metadata.objectValue?["display_precision"], .string("band_only"))
            XCTAssertTrue(evidence.clientIdempotencyKey.hasPrefix("calibration-v1:"))
        }
        XCTAssertEqual(BaselineCalibrationAuthority.standard.canReplaceProgramme, false)
        XCTAssertEqual(BaselineCalibrationAuthority.bespoke.canReplaceProgramme, false)
        XCTAssertEqual(BaselineCalibrationAuthority.bespoke.canAuthorizeBespoke, false)
    }

    func testRecentResultBuilderValidatesAndKeepsUserConfidenceLow() throws {
        let fixture: BaselineCalibrationFixture = try decodeCalibrationFixture()
        let accepted = BaselineCalibrationAssessment.manualEvidence(
            userID: fixture.userID,
            metric: .restingMetabolicRate,
            value: 1_683,
            unit: "kcal_per_day",
            declaredSource: "DEXA report",
            measuredAt: fixture.measuredAt,
            importedAt: fixture.importedAt
        )
        guard case .accepted(let evidence) = accepted else {
            return XCTFail("Expected valid external result")
        }
        XCTAssertEqual(evidence.source, .userEnteredExternalResult)
        XCTAssertEqual(evidence.confidence, .low)
        XCTAssertEqual(evidence.metadata["declared_source"], .string("DEXA report"))

        let rejected = BaselineCalibrationAssessment.manualEvidence(
            userID: fixture.userID,
            metric: .vo2Max,
            value: 999,
            unit: "ml_per_kg_min",
            declaredSource: "Lab result",
            measuredAt: fixture.measuredAt,
            importedAt: fixture.importedAt
        )
        XCTAssertEqual(rejected, .rejected("invalid_unit_or_range"))
    }

    func testDEXAReportCanPersistBodyFatAndPrintedRestingEnergyTogether() throws {
        let fixture: BaselineCalibrationFixture = try decodeCalibrationFixture()
        let result = BaselineCalibrationAssessment.manualDEXAEvidence(
            userID: fixture.userID,
            bodyFatPercentage: 18.4,
            restingMetabolicRate: 1_683,
            declaredSource: "DEXA report · clinic copy",
            measuredAt: fixture.measuredAt,
            importedAt: fixture.importedAt
        )
        guard case .accepted(let evidence) = result else {
            return XCTFail("Expected two DEXA evidence records")
        }
        XCTAssertEqual(evidence.map(\.metric), [.bodyFatPercentage, .restingMetabolicRate])
        XCTAssertTrue(evidence.allSatisfy { $0.confidence == .low })
        XCTAssertTrue(evidence.allSatisfy {
            $0.metadata["declared_source"] == .string("DEXA report · clinic copy")
        })
        XCTAssertEqual(
            BaselineCalibrationAssessment.manualDEXAEvidence(
                userID: fixture.userID,
                bodyFatPercentage: nil,
                restingMetabolicRate: nil,
                declaredSource: "DEXA report",
                measuredAt: fixture.measuredAt,
                importedAt: fixture.importedAt
            ),
            .rejected("missing_value")
        )
    }

    private func decodeCalibrationFixture<T: Decodable>() throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "baseline-calibration",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func calibrationEvidence(
        owner: UUID,
        metric: FitnessEvidenceMetric,
        value: Double = 30,
        importedAt: String = "2026-08-31T08:00:01Z"
    ) -> FitnessEvidenceRecord {
        FitnessEvidenceRecord(
            id: UUID(),
            userID: owner,
            metric: metric,
            value: value,
            unit: "score_0_100",
            source: .structuredSelfReport,
            protocol: "apex_baseline_calibration_v1",
            device: nil,
            measuredAt: "2026-08-31T08:00:00Z",
            importedAt: importedAt,
            confidence: .low,
            metadata: [
                "answered_count": .number(3),
                "display_precision": .string("band_only"),
            ],
            supersedesID: nil,
            clientIdempotencyKey: "calibration-v1:\(owner.uuidString.lowercased()):\(metric.rawValue)"
        )
    }
}
