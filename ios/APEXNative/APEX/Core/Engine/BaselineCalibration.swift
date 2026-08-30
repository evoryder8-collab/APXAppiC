import Foundation

enum BaselineCalibrationAnswer: String, Codable, Sendable, CaseIterable {
    case notTested = "not_tested"
    case foundation, developing, capable, strong
}

struct BaselineCalibrationAnswers: Codable, Sendable, Equatable {
    var cardiorespiratory: [String]
    var upperStrength: [String]
    var lowerStrength: [String]
    var mobility: [String]

    enum CodingKeys: String, CodingKey {
        case cardiorespiratory, mobility
        case upperStrength = "upper_strength"
        case lowerStrength = "lower_strength"
    }

    static let empty = BaselineCalibrationAnswers(
        cardiorespiratory: Array(repeating: BaselineCalibrationAnswer.notTested.rawValue, count: 3),
        upperStrength: Array(repeating: BaselineCalibrationAnswer.notTested.rawValue, count: 3),
        lowerStrength: Array(repeating: BaselineCalibrationAnswer.notTested.rawValue, count: 3),
        mobility: Array(repeating: BaselineCalibrationAnswer.notTested.rawValue, count: 3)
    )

    func values(for domain: OnboardingMovementDomain) -> [String] {
        switch domain {
        case .cardiorespiratory: cardiorespiratory
        case .upperStrength: upperStrength
        case .lowerStrength: lowerStrength
        case .mobility: mobility
        }
    }

    fileprivate var isValidDraft: Bool {
        OnboardingMovementDomain.allCases.allSatisfy { domain in
            let submitted = values(for: domain)
            return submitted.count == 3 && submitted.allSatisfy {
                BaselineCalibrationAnswer(rawValue: $0) != nil
            }
        }
    }
}

struct BaselineCalibrationEvaluation: Sendable, Equatable {
    var bands: OnboardingBaselineBands
    var evidence: [FitnessEvidenceDraft]
}

enum BaselineCalibrationResult: Sendable, Equatable {
    case accepted(BaselineCalibrationEvaluation)
    case rejected(String)
}

enum BaselineCalibrationSaveError: Error, Sendable {
    case missingAccount
    case invalidAssessment
    case invalidEvidence
}

struct BaselineCalibrationEvidenceSummary: Codable, Sendable, Equatable {
    var metric: String
    var value: Double
    var lowerBound: Double
    var upperBound: Double
    var band: OnboardingBaselineBand
    var answeredCount: Int

    enum CodingKeys: String, CodingKey {
        case metric, value, band
        case lowerBound = "lower_bound"
        case upperBound = "upper_bound"
        case answeredCount = "answered_count"
    }
}

struct BaselineCalibrationSummary: Codable, Sendable, Equatable {
    var status: String
    var bands: OnboardingBaselineBands?
    var evidence: [BaselineCalibrationEvidenceSummary]?
    var reason: String?
}

struct BaselineCalibrationFixture: Codable, Sendable {
    struct Scenario: Codable, Sendable {
        var name: String
        var input: BaselineCalibrationAnswers
        var expected: BaselineCalibrationSummary
    }

    var version: Int
    var userID: String
    var measuredAt: String
    var importedAt: String
    var scenarios: [Scenario]

    enum CodingKeys: String, CodingKey {
        case version, scenarios
        case userID = "user_id"
        case measuredAt = "measured_at"
        case importedAt = "imported_at"
    }
}

struct BaselineCalibrationDraft: Codable, Sendable, Equatable {
    var step: Int
    var answers: BaselineCalibrationAnswers

    static let empty = BaselineCalibrationDraft(step: 0, answers: .empty)
}

enum BaselineCalibrationAuthority: String, Sendable {
    case standard, bespoke

    var canRefineEvidence: Bool { true }
    var canReplaceProgramme: Bool { false }
    var canAuthorizeBespoke: Bool { false }
}

enum BaselineCalibrationDraftStore {
    private static func key(userID: UUID) -> String {
        "apex.baseline-calibration.v1.\(userID.uuidString.lowercased())"
    }

    static func load(userID: UUID, defaults: UserDefaults = .standard) -> BaselineCalibrationDraft? {
        guard let data = defaults.data(forKey: key(userID: userID)),
              let draft = try? JSONDecoder().decode(BaselineCalibrationDraft.self, from: data),
              (0...8).contains(draft.step),
              draft.answers.isValidDraft else { return nil }
        return draft
    }

    static func save(
        _ draft: BaselineCalibrationDraft,
        userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        guard draft.answers.isValidDraft,
              let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(userID: userID))
    }

    static func clear(userID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userID: userID))
    }
}

enum BaselineCalibrationAssessment {
    static let version = 1

    private struct Definition {
        let value: Double
        let lower: Double
        let upper: Double
        let rank: Int
    }

    private static let definitions: [BaselineCalibrationAnswer: Definition] = [
        .foundation: Definition(value: 30, lower: 20, upper: 39, rank: 0),
        .developing: Definition(value: 47, lower: 40, upper: 54, rank: 1),
        .capable: Definition(value: 62, lower: 55, upper: 69, rank: 2),
        .strong: Definition(value: 77, lower: 70, upper: 84, rank: 3),
    ]

    private static let metrics: [OnboardingMovementDomain: FitnessEvidenceMetric] = [
        .cardiorespiratory: .cardioCapacityScore,
        .upperStrength: .upperBodyStrengthScore,
        .lowerStrength: .lowerBodyStrengthScore,
        .mobility: .flexibilityScore,
    ]

    static func evaluate(
        userID: String,
        measuredAt: String,
        importedAt: String,
        answers: BaselineCalibrationAnswers
    ) -> BaselineCalibrationResult {
        let owner = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty,
              ISO8601DateFormatter().date(from: measuredAt) != nil,
              ISO8601DateFormatter().date(from: importedAt) != nil else {
            return .rejected("invalid_boundary")
        }

        var bands = OnboardingBaselineBands(
            cardiorespiratory: .buildingBaseline,
            upperStrength: .buildingBaseline,
            lowerStrength: .buildingBaseline,
            mobility: .buildingBaseline,
            overallFitness: .buildingBaseline
        )
        var evidence: [FitnessEvidenceDraft] = []

        for domain in OnboardingMovementDomain.allCases {
            let submitted = answers.values(for: domain)
            guard submitted.count == 3 else { return .rejected("unsupported_answer") }
            let parsed = submitted.compactMap(BaselineCalibrationAnswer.init(rawValue:))
            guard parsed.count == 3 else { return .rejected("unsupported_answer") }
            let answered = parsed.filter { $0 != .notTested }
            guard answered.count >= 2 else { continue }
            let ordered = answered.sorted {
                (definitions[$0]?.rank ?? -1) < (definitions[$1]?.rank ?? -1)
            }
            let median = ordered[(ordered.count - 1) / 2]
            guard let definition = definitions[median],
                  let metric = metrics[domain],
                  let band = OnboardingBaselineBand(rawValue: median.rawValue) else {
                return .rejected("unsupported_answer")
            }
            let lower = answered.compactMap { definitions[$0]?.lower }.min() ?? definition.lower
            let upper = answered.compactMap { definitions[$0]?.upper }.max() ?? definition.upper
            switch domain {
            case .cardiorespiratory: bands.cardiorespiratory = band
            case .upperStrength: bands.upperStrength = band
            case .lowerStrength: bands.lowerStrength = band
            case .mobility: bands.mobility = band
            }
            let digest = stableHash("\(domain.rawValue):\(submitted.joined(separator: ","))")
            evidence.append(FitnessEvidenceDraft(
                userID: owner,
                metric: metric.rawValue,
                value: definition.value,
                unit: "score_0_100",
                source: FitnessEvidenceSource.structuredSelfReport.rawValue,
                protocol: "apex_baseline_calibration_v1",
                device: nil,
                measuredAt: measuredAt,
                importedAt: importedAt,
                requestedConfidence: FitnessEvidenceConfidence.low.rawValue,
                metadata: .object([
                    "calibration_version": .number(Double(version)),
                    "route": .string("manual_questionnaire"),
                    "domain": .string(domain.rawValue),
                    "anchors": .array(submitted.map(JSONValue.string)),
                    "answered_count": .number(Double(answered.count)),
                    "band": .string(band.rawValue),
                    "lower_bound": .number(lower),
                    "upper_bound": .number(upper),
                    "display_precision": .string("band_only"),
                ]),
                supersedesID: nil,
                clientIdempotencyKey: [
                    "calibration-v1", owner, metric.rawValue,
                    String(measuredAt.prefix(10)), digest,
                ].joined(separator: ":")
            ))
        }

        return .accepted(BaselineCalibrationEvaluation(bands: bands, evidence: evidence))
    }

    static func summarize(_ result: BaselineCalibrationResult) -> BaselineCalibrationSummary {
        switch result {
        case .rejected(let reason):
            BaselineCalibrationSummary(status: "rejected", bands: nil, evidence: nil, reason: reason)
        case .accepted(let evaluation):
            BaselineCalibrationSummary(
                status: "accepted",
                bands: evaluation.bands,
                evidence: evaluation.evidence.map { item in
                    let metadata = item.metadata.objectValue ?? [:]
                    return BaselineCalibrationEvidenceSummary(
                        metric: item.metric,
                        value: item.value,
                        lowerBound: metadata["lower_bound"]?.numberValue ?? 0,
                        upperBound: metadata["upper_bound"]?.numberValue ?? 0,
                        band: OnboardingBaselineBand(
                            rawValue: metadata["band"]?.stringValue ?? ""
                        ) ?? .buildingBaseline,
                        answeredCount: Int(metadata["answered_count"]?.numberValue ?? 0)
                    )
                },
                reason: nil
            )
        }
    }

    static func manualEvidence(
        userID: String,
        metric: FitnessEvidenceMetric,
        value: Double,
        unit: String,
        declaredSource: String,
        measuredAt: String,
        importedAt: String
    ) -> FitnessEvidenceNormalizationResult {
        let declared = declaredSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !declared.isEmpty, declared.count <= 80 else {
            return .rejected("invalid_text_field")
        }
        let digest = stableHash(
            "\(metric.rawValue):\(value):\(unit):\(declared.lowercased())"
        )
        let draft = FitnessEvidenceDraft(
            userID: userID,
            metric: metric.rawValue,
            value: value,
            unit: unit,
            source: FitnessEvidenceSource.userEnteredExternalResult.rawValue,
            protocol: "apex_manual_result_v1",
            device: nil,
            measuredAt: measuredAt,
            importedAt: importedAt,
            requestedConfidence: FitnessEvidenceConfidence.low.rawValue,
            metadata: .object([
                "calibration_version": .number(Double(version)),
                "route": .string("recent_result"),
                "declared_source": .string(declared),
                "verification": .string("user_entered"),
            ]),
            supersedesID: nil,
            clientIdempotencyKey: [
                "calibration-result-v1", userID, metric.rawValue,
                String(measuredAt.prefix(10)), digest,
            ].joined(separator: ":")
        )
        return FitnessEvidenceNormalizer.normalize(
            draft,
            admission: .user,
            referenceNow: importedAt
        )
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }
}
