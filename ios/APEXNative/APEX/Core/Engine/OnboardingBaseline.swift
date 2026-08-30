import Foundation

enum OnboardingMovementDomain: String, Codable, Sendable, CaseIterable {
    case cardiorespiratory
    case upperStrength = "upper_strength"
    case lowerStrength = "lower_strength"
    case mobility
}

enum OnboardingActivityPattern: String, Codable, Sendable {
    case mostlySeated = "mostly_seated"
    case mixedDay = "mixed_day"
    case onFeet = "on_feet"
    case physicalWork = "physical_work"
    case notSure = "not_sure"

    var activityLevel: ActivityLevel {
        switch self {
        case .mostlySeated, .notSure: .sedentary
        case .mixedDay: .light
        case .onFeet: .moderate
        case .physicalWork: .very
        }
    }
}

enum OnboardingMovementAnswer: String, Codable, Sendable {
    case notTested = "not_tested"
    case foundation, developing, capable, strong
}

enum OnboardingBaselineBand: String, Codable, Sendable, Equatable {
    case buildingBaseline = "building_baseline"
    case foundation, developing, capable, strong
}

struct OnboardingBaselineAnswers: Codable, Sendable, Equatable {
    var activityPattern: String
    var cardiorespiratory: String
    var upperStrength: String
    var lowerStrength: String
    var mobility: String

    enum CodingKeys: String, CodingKey {
        case activityPattern = "activity_pattern"
        case cardiorespiratory, mobility
        case upperStrength = "upper_strength"
        case lowerStrength = "lower_strength"
    }

    static let unanswered = OnboardingBaselineAnswers(
        activityPattern: "",
        cardiorespiratory: "",
        upperStrength: "",
        lowerStrength: "",
        mobility: ""
    )
}

struct OnboardingBaselineBands: Codable, Sendable, Equatable {
    var cardiorespiratory: OnboardingBaselineBand
    var upperStrength: OnboardingBaselineBand
    var lowerStrength: OnboardingBaselineBand
    var mobility: OnboardingBaselineBand
    var overallFitness: OnboardingBaselineBand

    enum CodingKeys: String, CodingKey {
        case cardiorespiratory, mobility
        case upperStrength = "upper_strength"
        case lowerStrength = "lower_strength"
        case overallFitness = "overall_fitness"
    }
}

struct OnboardingBaselineEvaluation: Sendable, Equatable {
    var activityLevel: ActivityLevel
    var bands: OnboardingBaselineBands
    var evidence: [FitnessEvidenceDraft]
}

enum OnboardingBaselineResult: Sendable, Equatable {
    case accepted(OnboardingBaselineEvaluation)
    case rejected(String)
}

struct OnboardingBaselineEvidenceSummary: Codable, Sendable, Equatable {
    var metric: String
    var value: Double
    var lowerBound: Double
    var upperBound: Double
    var band: OnboardingBaselineBand

    enum CodingKeys: String, CodingKey {
        case metric, value, band
        case lowerBound = "lower_bound"
        case upperBound = "upper_bound"
    }
}

struct OnboardingBaselineSummary: Codable, Sendable, Equatable {
    var status: String
    var activityLevel: String?
    var bands: OnboardingBaselineBands?
    var evidence: [OnboardingBaselineEvidenceSummary]?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case status, bands, evidence, reason
        case activityLevel = "activity_level"
    }
}

struct OnboardingBaselineFixture: Codable, Sendable {
    struct Scenario: Codable, Sendable {
        var name: String
        var input: OnboardingBaselineAnswers
        var expected: OnboardingBaselineSummary
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

enum OnboardingBaselineAssessment {
    static let version = 1
    static let movementDomains = OnboardingMovementDomain.allCases

    private struct BandDefinition {
        let value: Double
        let lowerBound: Double
        let upperBound: Double
    }

    private static let bandDefinitions: [OnboardingMovementAnswer: BandDefinition] = [
        .foundation: BandDefinition(value: 30, lowerBound: 20, upperBound: 39),
        .developing: BandDefinition(value: 47, lowerBound: 40, upperBound: 54),
        .capable: BandDefinition(value: 62, lowerBound: 55, upperBound: 69),
        .strong: BandDefinition(value: 77, lowerBound: 70, upperBound: 84),
    ]

    private static let evidenceMetrics: [OnboardingMovementDomain: FitnessEvidenceMetric] = [
        .cardiorespiratory: .cardioCapacityScore,
        .upperStrength: .upperBodyStrengthScore,
        .lowerStrength: .lowerBodyStrengthScore,
        .mobility: .flexibilityScore,
    ]

    static func evaluate(
        userID: String,
        measuredAt: String,
        importedAt: String,
        answers: OnboardingBaselineAnswers
    ) -> OnboardingBaselineResult {
        let owner = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty,
              ISO8601DateFormatter().date(from: measuredAt) != nil,
              ISO8601DateFormatter().date(from: importedAt) != nil else {
            return .rejected("invalid_boundary")
        }
        guard let activityPattern = OnboardingActivityPattern(rawValue: answers.activityPattern) else {
            return .rejected("unsupported_answer")
        }

        let rawAnswers: [OnboardingMovementDomain: String] = [
            .cardiorespiratory: answers.cardiorespiratory,
            .upperStrength: answers.upperStrength,
            .lowerStrength: answers.lowerStrength,
            .mobility: answers.mobility,
        ]
        var parsed: [OnboardingMovementDomain: OnboardingMovementAnswer] = [:]
        for domain in movementDomains {
            guard let answer = rawAnswers[domain].flatMap(OnboardingMovementAnswer.init(rawValue:)) else {
                return .rejected("unsupported_answer")
            }
            parsed[domain] = answer
        }

        var evidence: [FitnessEvidenceDraft] = []
        var resolvedBands: [OnboardingMovementDomain: OnboardingBaselineBand] = [:]
        for domain in movementDomains {
            guard let answer = parsed[domain] else { return .rejected("unsupported_answer") }
            if answer == .notTested {
                resolvedBands[domain] = .buildingBaseline
                continue
            }
            guard let definition = bandDefinitions[answer],
                  let metric = evidenceMetrics[domain],
                  let band = OnboardingBaselineBand(rawValue: answer.rawValue) else {
                return .rejected("unsupported_answer")
            }
            resolvedBands[domain] = band
            evidence.append(FitnessEvidenceDraft(
                userID: owner,
                metric: metric.rawValue,
                value: definition.value,
                unit: "score_0_100",
                source: FitnessEvidenceSource.structuredSelfReport.rawValue,
                protocol: "apex_onboarding_pulse_v1",
                device: nil,
                measuredAt: measuredAt,
                importedAt: importedAt,
                requestedConfidence: FitnessEvidenceConfidence.low.rawValue,
                metadata: .object([
                    "assessment_version": .number(Double(version)),
                    "anchor": .string(answer.rawValue),
                    "band": .string(band.rawValue),
                    "domain": .string(domain.rawValue),
                    "lower_bound": .number(definition.lowerBound),
                    "upper_bound": .number(definition.upperBound),
                    "display_precision": .string("band_only"),
                ]),
                supersedesID: nil,
                clientIdempotencyKey: stableEvidenceKey(
                    userID: owner,
                    metric: metric.rawValue,
                    answer: answer.rawValue,
                    measuredAt: measuredAt
                )
            ))
        }

        return .accepted(OnboardingBaselineEvaluation(
            activityLevel: activityPattern.activityLevel,
            bands: OnboardingBaselineBands(
                cardiorespiratory: resolvedBands[.cardiorespiratory] ?? .buildingBaseline,
                upperStrength: resolvedBands[.upperStrength] ?? .buildingBaseline,
                lowerStrength: resolvedBands[.lowerStrength] ?? .buildingBaseline,
                mobility: resolvedBands[.mobility] ?? .buildingBaseline,
                overallFitness: .buildingBaseline
            ),
            evidence: evidence
        ))
    }

    static func summarize(_ result: OnboardingBaselineResult) -> OnboardingBaselineSummary {
        switch result {
        case .rejected(let reason):
            OnboardingBaselineSummary(
                status: "rejected",
                activityLevel: nil,
                bands: nil,
                evidence: nil,
                reason: reason
            )
        case .accepted(let evaluation):
            OnboardingBaselineSummary(
                status: "accepted",
                activityLevel: evaluation.activityLevel.rawValue,
                bands: evaluation.bands,
                evidence: evaluation.evidence.map { item in
                    let metadata = item.metadata.objectValue ?? [:]
                    return OnboardingBaselineEvidenceSummary(
                        metric: item.metric,
                        value: item.value,
                        lowerBound: metadata["lower_bound"]?.numberValue ?? 0,
                        upperBound: metadata["upper_bound"]?.numberValue ?? 0,
                        band: OnboardingBaselineBand(
                            rawValue: metadata["band"]?.stringValue ?? ""
                        ) ?? .buildingBaseline
                    )
                },
                reason: nil
            )
        }
    }

    static func stableEvidenceKey(
        userID: String,
        metric: String,
        answer: String,
        measuredAt: String
    ) -> String {
        ["onboarding-v1", userID, metric, answer, String(measuredAt.prefix(10))]
            .joined(separator: ":")
    }
}
