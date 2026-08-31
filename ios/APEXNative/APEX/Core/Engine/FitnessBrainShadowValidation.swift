import Foundation

enum FitnessBrainShadowPlatform: String, Codable, Sendable, Equatable {
    case web, ios
}

enum FitnessBrainShadowProfileKind: String, Codable, Sendable, Equatable {
    case standard, bespoke
}

enum FitnessBrainShadowAgeBand: String, Codable, Sendable, Equatable {
    case under30 = "under_30"
    case age30To44 = "30_44"
    case age45To59 = "45_59"
    case age60Plus = "60_plus"
    case unknown
}

enum FitnessBrainShadowSexGroup: String, Codable, Sendable, Equatable {
    case female, male, unknown
}

enum FitnessBrainLegacyOverallBand: String, Codable, Sendable, Equatable {
    case unavailable
    case score0To19 = "0_19"
    case score20To39 = "20_39"
    case score40To59 = "40_59"
    case score60To79 = "60_79"
    case score80To100 = "80_100"
}

enum FitnessBrainShadowDisagreementBand: String, Codable, Sendable, Equatable {
    case unavailable
    case under5 = "under_5"
    case score5To14 = "5_to_14"
    case score15To24 = "15_to_24"
    case score25Plus = "25_plus"
}

enum FitnessBrainShadowCoverageBand: String, Codable, Sendable, Equatable {
    case none, low, partial, sufficient
}

enum FitnessBrainShadowInvariantCode: String, Codable, Sendable, Equatable, Comparable {
    case missingDataChangedCapacity = "missing_data_changed_capacity"
    case readinessChangedCapacity = "readiness_changed_capacity"
    case adherenceChangedCapacity = "adherence_changed_capacity"
    case adaptationChangedCapacity = "adaptation_changed_capacity"
    case healthContextChangedCapacity = "health_context_changed_capacity"
    case overallConfidenceExceededDomain = "overall_confidence_exceeded_domain"
    case capacityValueOutsideBounds = "capacity_value_outside_bounds"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct FitnessBrainShadowRunInput: Codable, Sendable, Equatable {
    var observedOn: String
    var platform: FitnessBrainShadowPlatform
    var profileKind: FitnessBrainShadowProfileKind
    var ageBand: FitnessBrainShadowAgeBand
    var sexGroup: FitnessBrainShadowSexGroup
    var legacyOverall: Double?
    var v2Input: FitnessBrainV2Input

    enum CodingKeys: String, CodingKey {
        case platform
        case observedOn = "observed_on"
        case profileKind = "profile_kind"
        case ageBand = "age_band"
        case sexGroup = "sex_group"
        case legacyOverall = "legacy_overall"
        case v2Input = "v2_input"
    }
}

struct FitnessBrainShadowObservation: Codable, Sendable, Equatable {
    var observedOn: String
    var platform: FitnessBrainShadowPlatform
    var profileKind: FitnessBrainShadowProfileKind
    var ageBand: FitnessBrainShadowAgeBand
    var sexGroup: FitnessBrainShadowSexGroup
    var presentationModelVersion: Int
    var shadowModelVersion: Int
    var legacyOverallBand: FitnessBrainLegacyOverallBand
    var shadowOverallBand: FBV2CapacityBand
    var absoluteDisagreementBand: FitnessBrainShadowDisagreementBand
    var overallCoverageBand: FitnessBrainShadowCoverageBand
    var overallConfidence: FBV2Confidence
    var sourceDistribution: [String: Int]
    var issueCodes: [String]
    var invariantCodes: [FitnessBrainShadowInvariantCode]

    enum CodingKeys: String, CodingKey {
        case platform
        case observedOn = "observed_on"
        case profileKind = "profile_kind"
        case ageBand = "age_band"
        case sexGroup = "sex_group"
        case presentationModelVersion = "presentation_model_version"
        case shadowModelVersion = "shadow_model_version"
        case legacyOverallBand = "legacy_overall_band"
        case shadowOverallBand = "shadow_overall_band"
        case absoluteDisagreementBand = "absolute_disagreement_band"
        case overallCoverageBand = "overall_coverage_band"
        case overallConfidence = "overall_confidence"
        case sourceDistribution = "source_distribution"
        case issueCodes = "issue_codes"
        case invariantCodes = "invariant_codes"
    }
}

struct FitnessBrainShadowRPCParameters: Codable, Sendable, Equatable {
    var observedOn: String
    var platform: FitnessBrainShadowPlatform
    var presentationModelVersion: Int
    var shadowModelVersion: Int
    var legacyOverallBand: FitnessBrainLegacyOverallBand
    var shadowOverallBand: FBV2CapacityBand
    var absoluteDisagreementBand: FitnessBrainShadowDisagreementBand
    var overallCoverageBand: FitnessBrainShadowCoverageBand
    var overallConfidence: FBV2Confidence
    var sourceDistribution: [String: Int]
    var issueCodes: [String]
    var invariantCodes: [FitnessBrainShadowInvariantCode]

    init(observation: FitnessBrainShadowObservation) {
        observedOn = observation.observedOn
        platform = observation.platform
        presentationModelVersion = observation.presentationModelVersion
        shadowModelVersion = observation.shadowModelVersion
        legacyOverallBand = observation.legacyOverallBand
        shadowOverallBand = observation.shadowOverallBand
        absoluteDisagreementBand = observation.absoluteDisagreementBand
        overallCoverageBand = observation.overallCoverageBand
        overallConfidence = observation.overallConfidence
        sourceDistribution = observation.sourceDistribution
        issueCodes = observation.issueCodes
        invariantCodes = observation.invariantCodes
    }

    var outboxKey: String {
        ["fitness-brain-shadow", observedOn, platform.rawValue, String(shadowModelVersion)]
            .joined(separator: ":")
    }

    enum CodingKeys: String, CodingKey {
        case observedOn = "p_observed_on"
        case platform = "p_platform"
        case presentationModelVersion = "p_presentation_model_version"
        case shadowModelVersion = "p_shadow_model_version"
        case legacyOverallBand = "p_legacy_overall_band"
        case shadowOverallBand = "p_shadow_overall_band"
        case absoluteDisagreementBand = "p_absolute_disagreement_band"
        case overallCoverageBand = "p_overall_coverage_band"
        case overallConfidence = "p_overall_confidence"
        case sourceDistribution = "p_source_distribution"
        case issueCodes = "p_issue_codes"
        case invariantCodes = "p_invariant_codes"
    }
}

struct FitnessBrainShadowFixture: Codable, Sendable {
    struct Scenario: Codable, Sendable {
        var name: String
        var input: FitnessBrainShadowRunInput
        var expected: FitnessBrainShadowObservation
    }

    var scenarios: [Scenario]
}

struct FitnessBrainShadowRolloutEvidence: Sendable, Equatable {
    var observationCount: Int
    var smallestSubgroupCount: Int
    var sufficientCoverageRate: Double
    var disagreementOutlierRate: Double
    var invariantViolationCount: Int
    var scientificReviewComplete: Bool
    var privacyReviewComplete: Bool
    var claimReviewComplete: Bool
    var ownerActivationApproved: Bool
}

enum FitnessBrainShadowRolloutMode: String, Sendable, Equatable {
    case shadowOnly = "shadow_only"
    case eligibleForControlledActivation = "eligible_for_controlled_activation"
}

struct FitnessBrainShadowRolloutDecision: Sendable, Equatable {
    var mode: FitnessBrainShadowRolloutMode
    var blockers: [String]
}

enum FitnessBrainShadowValidator {
    static let presentationModelVersion = 1

    private static let capacityKeys = [
        FBV2CapacityDomain.cardiorespiratory.rawValue,
        FBV2CapacityDomain.upperStrength.rawValue,
        FBV2CapacityDomain.lowerStrength.rawValue,
        FBV2CapacityDomain.mobilityHipPosterior.rawValue,
        FBV2CapacityDomain.mobilityAnkle.rawValue,
        FBV2CapacityDomain.mobilityShoulder.rawValue,
        FBV2CapacityDomain.balanceFunction.rawValue,
        "mobility",
        "overall_fitness"
    ]
    private static let confidenceRank: [FBV2Confidence: Int] = [
        .unavailable: 0, .low: 1, .medium: 2, .high: 3
    ]
    private static let directMetricDomains: [FitnessEvidenceMetric: FBV2CapacityDomain] = [
        .cardioCapacityScore: .cardiorespiratory,
        .upperBodyStrengthScore: .upperStrength,
        .lowerBodyStrengthScore: .lowerStrength,
        .balanceScore: .balanceFunction
    ]
    private static let safeIssuePrefixes: Set<String> = [
        "duplicate_domain", "invalid_unknown", "missing_value", "invalid_bounds",
        "out_of_range", "non_finite", "invalid_coverage", "invalid_model_version",
        "invalid_reference_scale", "invalid_confidence", "missing_evidence",
        "missing_receipt", "band_too_narrow"
    ]

    static func compose(_ input: FitnessBrainShadowRunInput) -> FitnessBrainShadowObservation {
        let state = FitnessBrainV2.compose(input.v2Input)
        let overall = state.capacity["overall_fitness"]!
        return FitnessBrainShadowObservation(
            observedOn: input.observedOn,
            platform: input.platform,
            profileKind: input.profileKind,
            ageBand: input.ageBand,
            sexGroup: input.sexGroup,
            presentationModelVersion: presentationModelVersion,
            shadowModelVersion: FitnessBrainV2.modelVersion,
            legacyOverallBand: legacyBand(input.legacyOverall),
            shadowOverallBand: overall.band,
            absoluteDisagreementBand: disagreementBand(input.legacyOverall, overall.value),
            overallCoverageBand: coverageBand(overall.coverage),
            overallConfidence: overall.confidence,
            sourceDistribution: sourceDistribution(input.v2Input),
            issueCodes: Array(Set(state.issueCodes.filter(isSafeIssueCode))).sorted(),
            invariantCodes: auditInvariants(input.v2Input, state: state)
        )
    }

    static func runtimeObservation(
        ownerID: UUID,
        observedOn: String,
        platform: FitnessBrainShadowPlatform,
        profileKind: FitnessBrainShadowProfileKind,
        birthdate: String?,
        sex: String?,
        legacySnapshots: [RPGSnapshot],
        evidence: [FitnessEvidenceRecord]
    ) -> FitnessBrainShadowObservation {
        let latestLegacy = legacySnapshots
            .filter { $0.userID == ownerID && $0.date <= observedOn && $0.overall.isFinite }
            .max { $0.date < $1.date }
        let normalizedSex = sex?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return compose(FitnessBrainShadowRunInput(
            observedOn: observedOn,
            platform: platform,
            profileKind: profileKind,
            ageBand: runtimeAgeBand(birthdate, observedOn: observedOn),
            sexGroup: normalizedSex == "female" || normalizedSex == "woman"
                ? .female
                : normalizedSex == "male" || normalizedSex == "man" ? .male : .unknown,
            legacyOverall: latestLegacy?.overall,
            v2Input: FitnessBrainV2Input(
                asOf: observedOn,
                capacity: buildCapacityInputs(records: evidence, ownerID: ownerID, asOf: observedOn),
                readinessSignals: [],
                adherenceEvents: [],
                adaptationSignals: [],
                healthContext: .init(flags: [], receiptIDs: [])
            )
        ))
    }

    static func auditInvariants(
        _ input: FitnessBrainV2Input,
        state: FitnessBrainV2State? = nil
    ) -> [FitnessBrainShadowInvariantCode] {
        let baseline = state ?? FitnessBrainV2.compose(input)
        var codes = Set<FitnessBrainShadowInvariantCode>()

        var withoutReadiness = input
        withoutReadiness.readinessSignals = []
        if capacityChanged(baseline, FitnessBrainV2.compose(withoutReadiness)) {
            codes.insert(.readinessChangedCapacity)
        }

        var withoutAdherence = input
        withoutAdherence.adherenceEvents = []
        if capacityChanged(baseline, FitnessBrainV2.compose(withoutAdherence)) {
            codes.insert(.adherenceChangedCapacity)
        }

        var withoutAdaptation = input
        withoutAdaptation.adaptationSignals = []
        if capacityChanged(baseline, FitnessBrainV2.compose(withoutAdaptation)) {
            codes.insert(.adaptationChangedCapacity)
        }

        var withoutHealthContext = input
        withoutHealthContext.healthContext = .init(flags: [], receiptIDs: [])
        if capacityChanged(baseline, FitnessBrainV2.compose(withoutHealthContext)) {
            codes.insert(.healthContextChangedCapacity)
        }

        var withoutMissing = input
        withoutMissing.capacity.removeAll { $0.value == nil }
        if capacityChanged(baseline, FitnessBrainV2.compose(withoutMissing)) {
            codes.insert(.missingDataChangedCapacity)
        }

        if overallConfidenceExceedsDomain(baseline) {
            codes.insert(.overallConfidenceExceededDomain)
        }
        if containsValueOutsideBounds(baseline) {
            codes.insert(.capacityValueOutsideBounds)
        }
        return codes.sorted()
    }

    static func buildCapacityInputs(
        records: [FitnessEvidenceRecord],
        ownerID: UUID,
        asOf: String
    ) -> [FitnessBrainV2CapacityEstimateInput] {
        let owned = records.filter { $0.userID == ownerID }
        let supersededIDs = Set(owned.compactMap(\.supersedesID))
        var latest: [FBV2CapacityDomain: FitnessEvidenceRecord] = [:]

        for record in owned where !supersededIDs.contains(record.id) {
            guard let domain = directMetricDomains[record.metric] else { continue }
            guard let existing = latest[domain] else {
                latest[domain] = record
                continue
            }
            if chronologyKey(record) > chronologyKey(existing) {
                latest[domain] = record
            }
        }

        return latest.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { domain in
            latest[domain].flatMap { capacityInput($0, domain: domain, asOf: asOf) }
        }
    }

    static func evaluateRolloutGate(
        _ evidence: FitnessBrainShadowRolloutEvidence
    ) -> FitnessBrainShadowRolloutDecision {
        var blockers: [String] = []
        if evidence.observationCount < 1_000 { blockers.append("minimum_observations_not_met") }
        if evidence.smallestSubgroupCount < 100 { blockers.append("subgroup_sample_not_met") }
        if evidence.sufficientCoverageRate < 0.8 { blockers.append("coverage_not_met") }
        if evidence.disagreementOutlierRate > 0.05 { blockers.append("outlier_rate_too_high") }
        if evidence.invariantViolationCount != 0 { blockers.append("invariant_violation_present") }
        if !evidence.scientificReviewComplete { blockers.append("scientific_review_required") }
        if !evidence.privacyReviewComplete { blockers.append("privacy_review_required") }
        if !evidence.claimReviewComplete { blockers.append("claim_review_required") }
        if !evidence.ownerActivationApproved { blockers.append("owner_activation_required") }
        return FitnessBrainShadowRolloutDecision(
            mode: blockers.isEmpty ? .eligibleForControlledActivation : .shadowOnly,
            blockers: blockers
        )
    }

    private static func legacyBand(_ value: Double?) -> FitnessBrainLegacyOverallBand {
        guard let value, value.isFinite else { return .unavailable }
        if value < 20 { return .score0To19 }
        if value < 40 { return .score20To39 }
        if value < 60 { return .score40To59 }
        if value < 80 { return .score60To79 }
        return .score80To100
    }

    private static func runtimeAgeBand(_ birthdate: String?, observedOn: String) -> FitnessBrainShadowAgeBand {
        let birth = birthdate?.split(separator: "-").compactMap { Int($0) }
        let observed = observedOn.split(separator: "-").compactMap { Int($0) }
        guard let birth, birth.count == 3, observed.count == 3 else { return .unknown }
        let age = observed[0] - birth[0]
            - ((observed[1] * 100 + observed[2]) < (birth[1] * 100 + birth[2]) ? 1 : 0)
        guard (0...120).contains(age) else { return .unknown }
        if age < 30 { return .under30 }
        if age < 45 { return .age30To44 }
        if age < 60 { return .age45To59 }
        return .age60Plus
    }

    private static func disagreementBand(
        _ legacy: Double?,
        _ shadow: Double?
    ) -> FitnessBrainShadowDisagreementBand {
        guard let legacy, let shadow, legacy.isFinite, shadow.isFinite else { return .unavailable }
        let delta = abs(legacy - shadow)
        if delta < 5 { return .under5 }
        if delta < 15 { return .score5To14 }
        if delta < 25 { return .score15To24 }
        return .score25Plus
    }

    private static func coverageBand(_ coverage: Double) -> FitnessBrainShadowCoverageBand {
        if coverage <= 0 { return .none }
        if coverage < 0.35 { return .low }
        if coverage < 0.6 { return .partial }
        return .sufficient
    }

    private static func sourceDistribution(_ input: FitnessBrainV2Input) -> [String: Int] {
        input.capacity.reduce(into: [:]) { counts, estimate in
            guard estimate.sourceClass != .composite else { return }
            counts[estimate.sourceClass.rawValue, default: 0] += 1
        }
    }

    private static func isSafeIssueCode(_ code: String) -> Bool {
        let parts = code.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, safeIssuePrefixes.contains(String(parts[0])) else { return false }
        return !parts[1].isEmpty && parts[1].allSatisfy { $0.isLowercase || $0 == "_" }
    }

    private static func capacityChanged(_ left: FitnessBrainV2State, _ right: FitnessBrainV2State) -> Bool {
        capacityKeys.contains { left.capacity[$0] != right.capacity[$0] }
    }

    private static func containsValueOutsideBounds(_ state: FitnessBrainV2State) -> Bool {
        capacityKeys.contains { key in
            guard let estimate = state.capacity[key], let value = estimate.value else { return false }
            guard let lower = estimate.lowerBound, let upper = estimate.upperBound else { return true }
            return value < lower || value > upper
        }
    }

    private static func overallConfidenceExceedsDomain(_ state: FitnessBrainV2State) -> Bool {
        guard let overall = state.capacity["overall_fitness"], overall.confidence != .unavailable else {
            return false
        }
        let requiredKeys = [
            FBV2CapacityDomain.cardiorespiratory.rawValue,
            FBV2CapacityDomain.upperStrength.rawValue,
            FBV2CapacityDomain.lowerStrength.rawValue,
            "mobility"
        ]
        return requiredKeys.contains { key in
            guard let estimate = state.capacity[key] else { return true }
            return confidenceRank[overall.confidence, default: 0] > confidenceRank[estimate.confidence, default: 0]
        }
    }

    private static func chronologyKey(_ record: FitnessEvidenceRecord) -> String {
        "\(record.measuredAt):\(record.importedAt):\(record.id.uuidString)"
    }

    private static func capacityInput(
        _ record: FitnessEvidenceRecord,
        domain: FBV2CapacityDomain,
        asOf: String
    ) -> FitnessBrainV2CapacityEstimateInput? {
        guard record.unit == "score_0_100",
              let lower = record.metadata["lower_bound"]?.numberValue,
              let upper = record.metadata["upper_bound"]?.numberValue,
              lower >= 0,
              upper <= 100,
              lower <= record.value,
              upper >= record.value else {
            return nil
        }
        return FitnessBrainV2CapacityEstimateInput(
            domain: domain,
            value: record.value,
            lowerBound: lower,
            upperBound: upper,
            referenceScale: FitnessBrainV2.referenceScale,
            confidence: confidence(record.confidence),
            coverage: evidenceCoverage(record),
            freshness: freshness(record.measuredAt, asOf: asOf),
            sourceClass: sourceClass(record.source),
            evidenceIDs: [record.id.uuidString],
            explanationReceipts: [["evidence", record.metric.rawValue, record.id.uuidString].joined(separator: ":")],
            modelVersion: FitnessBrainV2.modelVersion,
            asOf: asOf
        )
    }

    private static func confidence(_ value: FitnessEvidenceConfidence) -> FBV2Confidence {
        switch value {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }

    private static func sourceClass(_ source: FitnessEvidenceSource) -> FBV2EvidenceSourceClass {
        switch source {
        case .supportedDevice: .supportedDevice
        case .guidedAPEXFieldTest: .guidedFieldTest
        case .indirectCalorimetry, .dexaMeasurement, .dexaDerivedEstimate, .clinicalMeasurement: .clinicalLab
        case .legacyUnverified: .legacyUnverified
        case .structuredSelfReport, .userEnteredExternalResult: .structuredSelfReport
        }
    }

    private static func evidenceCoverage(_ record: FitnessEvidenceRecord) -> Double {
        if let declared = record.metadata["coverage"]?.numberValue, declared.isFinite {
            return min(1, max(0, declared))
        }
        if let answered = record.metadata["answered_count"]?.numberValue, answered.isFinite {
            return min(0.55, max(0, answered / 3) * 0.55)
        }
        return record.source == .legacyUnverified ? 0.25 : 0.35
    }

    private static func freshness(_ measuredAt: String, asOf: String) -> FBV2Freshness {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let measured = formatter.date(from: measuredAt) ?? ISO8601DateFormatter().date(from: measuredAt)
        let current = ISO8601DateFormatter().date(from: asOf + "T" + "23:59:59Z")
        guard let measured, let current else { return .stale }
        let days = max(0, current.timeIntervalSince(measured) / 86_400)
        if days <= 90 { return .current }
        if days <= 365 { return .aging }
        return .stale
    }
}
