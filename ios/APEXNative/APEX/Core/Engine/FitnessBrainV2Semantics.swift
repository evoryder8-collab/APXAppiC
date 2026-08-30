import Foundation

enum FBV2Confidence: String, Codable, Sendable, Equatable {
    case unavailable, low, medium, high
}

enum FBV2Freshness: String, Codable, Sendable, Equatable {
    case current, aging, stale
}

enum FBV2CapacityDomain: String, Codable, Sendable, CaseIterable, Equatable {
    case cardiorespiratory
    case upperStrength = "upper_strength"
    case lowerStrength = "lower_strength"
    case mobilityHipPosterior = "mobility_hip_posterior"
    case mobilityAnkle = "mobility_ankle"
    case mobilityShoulder = "mobility_shoulder"
    case balanceFunction = "balance_function"
}

enum FBV2EvidenceSourceClass: String, Codable, Sendable, Equatable {
    case structuredSelfReport = "structured_self_report"
    case legacyUnverified = "legacy_unverified"
    case supportedDevice = "supported_device"
    case guidedFieldTest = "guided_field_test"
    case standardizedFieldTest = "standardized_field_test"
    case clinicalLab = "clinical_lab"
    case composite
}

enum FBV2CapacityBand: String, Codable, Sendable, Equatable {
    case buildingBaseline = "building_baseline"
    case foundation, developing, capable, strong, exceptional
}

enum FBV2ReadinessBand: String, Codable, Sendable, Equatable {
    case buildingBaseline = "building_baseline"
    case reduced, mixed, ready, strong
}

enum FBV2AdaptationBand: String, Codable, Sendable, Equatable {
    case unknown, limited, supported, strong
}

enum FBV2AdaptationStatus: String, Codable, Sendable, Equatable {
    case supportive, limiting
}

enum FBV2HealthContextFlag: String, Codable, Sendable, Equatable {
    case pain
    case recentOperation = "recent_operation"
    case acuteSymptom = "acute_symptom"
    case clearanceRequired = "clearance_required"
}

struct FitnessBrainV2CapacityEstimateInput: Codable, Sendable, Equatable {
    var domain: FBV2CapacityDomain
    var value: Double?
    var lowerBound: Double?
    var upperBound: Double?
    var referenceScale: String
    var confidence: FBV2Confidence
    var coverage: Double
    var freshness: FBV2Freshness
    var sourceClass: FBV2EvidenceSourceClass
    var evidenceIDs: [String]
    var explanationReceipts: [String]
    var modelVersion: Int
    var asOf: String

    enum CodingKeys: String, CodingKey {
        case domain, value, confidence, coverage, freshness
        case lowerBound = "lower_bound"
        case upperBound = "upper_bound"
        case referenceScale = "reference_scale"
        case sourceClass = "source_class"
        case evidenceIDs = "evidence_ids"
        case explanationReceipts = "explanation_receipts"
        case modelVersion = "model_version"
        case asOf = "as_of"
    }
}

struct FitnessBrainV2ReadinessSignalInput: Codable, Sendable, Equatable {
    var kind: String
    var normalizedValue: Double
    var confidence: FBV2Confidence
    var freshness: FBV2Freshness
    var evidenceID: String

    enum CodingKeys: String, CodingKey {
        case kind, confidence, freshness
        case normalizedValue = "normalized_value"
        case evidenceID = "evidence_id"
    }
}

struct FitnessBrainV2AdherenceEventInput: Codable, Sendable, Equatable {
    var kind: String
    var xp: Double
    var receiptID: String

    enum CodingKeys: String, CodingKey {
        case kind, xp
        case receiptID = "receipt_id"
    }
}

struct FitnessBrainV2AdaptationSignalInput: Codable, Sendable, Equatable {
    var kind: String
    var status: FBV2AdaptationStatus
    var receiptID: String

    enum CodingKeys: String, CodingKey {
        case kind, status
        case receiptID = "receipt_id"
    }
}

struct FitnessBrainV2HealthContextInput: Codable, Sendable, Equatable {
    var flags: [FBV2HealthContextFlag]
    var receiptIDs: [String]

    enum CodingKeys: String, CodingKey {
        case flags
        case receiptIDs = "receipt_ids"
    }
}

struct FitnessBrainV2Input: Codable, Sendable, Equatable {
    var asOf: String
    var capacity: [FitnessBrainV2CapacityEstimateInput]
    var readinessSignals: [FitnessBrainV2ReadinessSignalInput]
    var adherenceEvents: [FitnessBrainV2AdherenceEventInput]
    var adaptationSignals: [FitnessBrainV2AdaptationSignalInput]
    var healthContext: FitnessBrainV2HealthContextInput

    enum CodingKeys: String, CodingKey {
        case capacity
        case asOf = "as_of"
        case readinessSignals = "readiness_signals"
        case adherenceEvents = "adherence_events"
        case adaptationSignals = "adaptation_signals"
        case healthContext = "health_context"
    }
}

struct FitnessBrainV2CapacityEstimate: Sendable, Equatable {
    var domain: String
    var value: Double?
    var lowerBound: Double?
    var upperBound: Double?
    var referenceScale: String
    var confidence: FBV2Confidence
    var coverage: Double
    var freshness: FBV2Freshness
    var sourceClass: FBV2EvidenceSourceClass
    var evidenceIDs: [String]
    var explanationReceipts: [String]
    var modelVersion: Int
    var asOf: String
    var band: FBV2CapacityBand
}

struct FitnessBrainV2Readiness: Sendable, Equatable {
    var value: Double?
    var confidence: FBV2Confidence
    var coverage: Double
    var freshness: FBV2Freshness
    var band: FBV2ReadinessBand
    var evidenceIDs: [String]
}

struct FitnessBrainV2Adherence: Sendable, Equatable {
    var xp: Int
    var receiptIDs: [String]
}

struct FitnessBrainV2AdaptationSupport: Sendable, Equatable {
    var band: FBV2AdaptationBand
    var coverage: Double
    var supportiveReceiptIDs: [String]
    var limitingReceiptIDs: [String]
}

struct FitnessBrainV2HealthContext: Sendable, Equatable {
    var flags: [FBV2HealthContextFlag]
    var receiptIDs: [String]
    var fieldTestEligible: Bool
}

struct FitnessBrainV2State: Sendable, Equatable {
    var modelVersion: Int
    var asOf: String
    var capacity: [String: FitnessBrainV2CapacityEstimate]
    var readiness: FitnessBrainV2Readiness
    var adherence: FitnessBrainV2Adherence
    var adaptationSupport: FitnessBrainV2AdaptationSupport
    var healthContext: FitnessBrainV2HealthContext
    var rejectedDomains: [FBV2CapacityDomain]
    var issueCodes: [String]
}

struct FitnessBrainV2Summary: Codable, Sendable, Equatable {
    var modelVersion: Int
    var cardiorespiratoryValue: Double?
    var upperStrengthValue: Double?
    var lowerStrengthValue: Double?
    var mobilityValue: Double?
    var mobilityLowerBound: Double?
    var mobilityUpperBound: Double?
    var mobilityConfidence: FBV2Confidence
    var mobilityCoverage: Double
    var mobilityFreshness: FBV2Freshness
    var overallValue: Double?
    var overallLowerBound: Double?
    var overallUpperBound: Double?
    var overallConfidence: FBV2Confidence
    var overallCoverage: Double
    var overallFreshness: FBV2Freshness
    var overallBand: FBV2CapacityBand
    var readinessValue: Double?
    var readinessConfidence: FBV2Confidence
    var readinessCoverage: Double
    var readinessFreshness: FBV2Freshness
    var readinessBand: FBV2ReadinessBand
    var adherenceXP: Int
    var adaptationBand: FBV2AdaptationBand
    var fieldTestEligible: Bool
    var rejectedDomains: [FBV2CapacityDomain]
    var issueCodes: [String]

    enum CodingKeys: String, CodingKey {
        case modelVersion = "model_version"
        case cardiorespiratoryValue = "cardiorespiratory_value"
        case upperStrengthValue = "upper_strength_value"
        case lowerStrengthValue = "lower_strength_value"
        case mobilityValue = "mobility_value"
        case mobilityLowerBound = "mobility_lower_bound"
        case mobilityUpperBound = "mobility_upper_bound"
        case mobilityConfidence = "mobility_confidence"
        case mobilityCoverage = "mobility_coverage"
        case mobilityFreshness = "mobility_freshness"
        case overallValue = "overall_value"
        case overallLowerBound = "overall_lower_bound"
        case overallUpperBound = "overall_upper_bound"
        case overallConfidence = "overall_confidence"
        case overallCoverage = "overall_coverage"
        case overallFreshness = "overall_freshness"
        case overallBand = "overall_band"
        case readinessValue = "readiness_value"
        case readinessConfidence = "readiness_confidence"
        case readinessCoverage = "readiness_coverage"
        case readinessFreshness = "readiness_freshness"
        case readinessBand = "readiness_band"
        case adherenceXP = "adherence_xp"
        case adaptationBand = "adaptation_band"
        case fieldTestEligible = "field_test_eligible"
        case rejectedDomains = "rejected_domains"
        case issueCodes = "issue_codes"
    }
}

struct FitnessBrainV2Fixture: Codable, Sendable {
    struct Scenario: Codable, Sendable {
        var name: String
        var input: FitnessBrainV2Input
        var expected: FitnessBrainV2Summary
    }

    var scenarios: [Scenario]
}

enum FitnessBrainV2 {
    static let modelVersion = 2
    static let referenceScale = "apex_capacity_percentile_v2"
    private static let mobilityDomains: [FBV2CapacityDomain] = [
        .mobilityHipPosterior, .mobilityAnkle, .mobilityShoulder
    ]
    private static let confidenceRank: [FBV2Confidence: Int] = [
        .unavailable: 0, .low: 1, .medium: 2, .high: 3
    ]
    private static let freshnessRank: [FBV2Freshness: Int] = [
        .current: 0, .aging: 1, .stale: 2
    ]
    private static let sourceConfidenceCap: [FBV2EvidenceSourceClass: FBV2Confidence] = [
        .structuredSelfReport: .low,
        .legacyUnverified: .low,
        .supportedDevice: .medium,
        .guidedFieldTest: .medium,
        .standardizedFieldTest: .high,
        .clinicalLab: .high
    ]
    private static let sourceCoverageCap: [FBV2EvidenceSourceClass: Double] = [
        .structuredSelfReport: 0.55,
        .legacyUnverified: 0.35,
        .supportedDevice: 0.8,
        .guidedFieldTest: 0.85,
        .standardizedFieldTest: 0.95,
        .clinicalLab: 1
    ]
    private static let freshnessConfidenceCap: [FBV2Freshness: FBV2Confidence] = [
        .current: .high, .aging: .medium, .stale: .low
    ]

    static func compose(_ input: FitnessBrainV2Input) -> FitnessBrainV2State {
        var issues: [String] = []
        var rejected = Set<FBV2CapacityDomain>()
        var capacity: [String: FitnessBrainV2CapacityEstimate] = [:]

        for domain in FBV2CapacityDomain.allCases {
            let candidates = input.capacity.filter { $0.domain == domain }
            if candidates.count > 1 {
                rejected.insert(domain)
                issues.append("duplicate_domain:\(domain.rawValue)")
                capacity[domain.rawValue] = unavailableEstimate(domain.rawValue, asOf: input.asOf)
                continue
            }
            guard let candidate = candidates.first else {
                capacity[domain.rawValue] = unavailableEstimate(domain.rawValue, asOf: input.asOf)
                continue
            }
            if let code = rejectionCode(candidate) {
                rejected.insert(domain)
                issues.append("\(code):\(domain.rawValue)")
                capacity[domain.rawValue] = unavailableEstimate(domain.rawValue, asOf: input.asOf)
                continue
            }
            capacity[domain.rawValue] = normalize(candidate) ?? unavailableEstimate(domain.rawValue, asOf: input.asOf)
        }

        let mobilityInputs = mobilityDomains.compactMap { domain -> FitnessBrainV2CapacityEstimate? in
            guard let estimate = capacity[domain.rawValue], estimate.value != nil else { return nil }
            return estimate
        }
        let mobilityCoverage = mobilityInputs.isEmpty
            ? 0
            : average(mobilityInputs.map(\.coverage)) * (Double(mobilityInputs.count) / Double(mobilityDomains.count))
        let mobility: FitnessBrainV2CapacityEstimate
        if mobilityInputs.count >= 2 {
            mobility = composite("mobility", estimates: mobilityInputs, asOf: input.asOf, coverage: mobilityCoverage)
        } else {
            mobility = unavailableEstimate(
                "mobility",
                asOf: input.asOf,
                coverage: mobilityCoverage,
                freshness: worstFreshness(mobilityInputs.map(\.freshness))
            )
        }
        capacity["mobility"] = mobility

        let cardio = capacity[FBV2CapacityDomain.cardiorespiratory.rawValue]!
        let upper = capacity[FBV2CapacityDomain.upperStrength.rawValue]!
        let lower = capacity[FBV2CapacityDomain.lowerStrength.rawValue]!
        let strengthInputs = [upper, lower].filter { $0.value != nil }
        let strengthCoverage = strengthInputs.count == 2
            ? average(strengthInputs.map(\.coverage))
            : strengthInputs.reduce(0) { $0 + $1.coverage } / 2
        let overallCoverage = round4((cardio.coverage + strengthCoverage + mobility.coverage) / 3)
        let overallInputs = [cardio, upper, lower, mobility]
        let availableOverallInputs = overallInputs.filter { $0.value != nil }
        let overallFreshness = worstFreshness(availableOverallInputs.map(\.freshness))
        let canComposeOverall = cardio.value != nil && upper.value != nil && lower.value != nil &&
            mobility.value != nil && overallCoverage >= 0.6

        if canComposeOverall {
            let strength = composite(
                "overall_fitness",
                estimates: [upper, lower],
                asOf: input.asOf,
                coverage: strengthCoverage
            )
            var overall = composite(
                "overall_fitness",
                estimates: [cardio, strength, mobility],
                asOf: input.asOf,
                coverage: overallCoverage
            )
            overall.confidence = minimumConfidence(overallInputs.map(\.confidence))
            overall.freshness = overallFreshness
            capacity["overall_fitness"] = overall
        } else {
            capacity["overall_fitness"] = unavailableEstimate(
                "overall_fitness",
                asOf: input.asOf,
                coverage: overallCoverage,
                freshness: overallFreshness
            )
        }

        let flags = Array(Set(input.healthContext.flags)).sorted { $0.rawValue < $1.rawValue }
        return FitnessBrainV2State(
            modelVersion: modelVersion,
            asOf: input.asOf,
            capacity: capacity,
            readiness: composeReadiness(input.readinessSignals),
            adherence: composeAdherence(input.adherenceEvents),
            adaptationSupport: composeAdaptation(input.adaptationSignals),
            healthContext: FitnessBrainV2HealthContext(
                flags: flags,
                receiptIDs: uniqueSorted(input.healthContext.receiptIDs),
                fieldTestEligible: flags.isEmpty
            ),
            rejectedDomains: FBV2CapacityDomain.allCases.filter(rejected.contains),
            issueCodes: issues.sorted()
        )
    }

    static func summarize(_ state: FitnessBrainV2State) -> FitnessBrainV2Summary {
        let cardio = state.capacity[FBV2CapacityDomain.cardiorespiratory.rawValue]!
        let upper = state.capacity[FBV2CapacityDomain.upperStrength.rawValue]!
        let lower = state.capacity[FBV2CapacityDomain.lowerStrength.rawValue]!
        let mobility = state.capacity["mobility"]!
        let overall = state.capacity["overall_fitness"]!
        return FitnessBrainV2Summary(
            modelVersion: state.modelVersion,
            cardiorespiratoryValue: optionalRound4(cardio.value),
            upperStrengthValue: optionalRound4(upper.value),
            lowerStrengthValue: optionalRound4(lower.value),
            mobilityValue: optionalRound4(mobility.value),
            mobilityLowerBound: optionalRound4(mobility.lowerBound),
            mobilityUpperBound: optionalRound4(mobility.upperBound),
            mobilityConfidence: mobility.confidence,
            mobilityCoverage: round4(mobility.coverage),
            mobilityFreshness: mobility.freshness,
            overallValue: optionalRound4(overall.value),
            overallLowerBound: optionalRound4(overall.lowerBound),
            overallUpperBound: optionalRound4(overall.upperBound),
            overallConfidence: overall.confidence,
            overallCoverage: round4(overall.coverage),
            overallFreshness: overall.freshness,
            overallBand: overall.band,
            readinessValue: optionalRound4(state.readiness.value),
            readinessConfidence: state.readiness.confidence,
            readinessCoverage: round4(state.readiness.coverage),
            readinessFreshness: state.readiness.freshness,
            readinessBand: state.readiness.band,
            adherenceXP: state.adherence.xp,
            adaptationBand: state.adaptationSupport.band,
            fieldTestEligible: state.healthContext.fieldTestEligible,
            rejectedDomains: state.rejectedDomains,
            issueCodes: state.issueCodes
        )
    }

    private static func normalize(
        _ input: FitnessBrainV2CapacityEstimateInput
    ) -> FitnessBrainV2CapacityEstimate? {
        guard let value = input.value,
              let lower = input.lowerBound,
              let upper = input.upperBound,
              input.sourceClass != .composite,
              let sourceCap = sourceConfidenceCap[input.sourceClass],
              let coverageCap = sourceCoverageCap[input.sourceClass],
              let freshnessCap = freshnessConfidenceCap[input.freshness]
        else { return nil }
        let confidence = minimumConfidence([input.confidence, sourceCap, freshnessCap])
        guard confidence != .unavailable else { return nil }
        return FitnessBrainV2CapacityEstimate(
            domain: input.domain.rawValue,
            value: value,
            lowerBound: lower,
            upperBound: upper,
            referenceScale: referenceScale,
            confidence: confidence,
            coverage: round4(min(input.coverage, coverageCap)),
            freshness: input.freshness,
            sourceClass: input.sourceClass,
            evidenceIDs: uniqueSorted(input.evidenceIDs),
            explanationReceipts: uniqueSorted(input.explanationReceipts),
            modelVersion: modelVersion,
            asOf: input.asOf,
            band: capacityBand(value)
        )
    }

    private static func rejectionCode(_ input: FitnessBrainV2CapacityEstimateInput) -> String? {
        let values = [input.value, input.lowerBound, input.upperBound]
        if values.allSatisfy({ $0 == nil }) {
            return input.confidence == .unavailable && input.coverage == 0 ? nil : "invalid_unknown"
        }
        guard let value = input.value, let lower = input.lowerBound, let upper = input.upperBound else {
            return "partial_range"
        }
        guard value.isFinite, lower.isFinite, upper.isFinite, input.coverage.isFinite else {
            return "non_finite"
        }
        guard (0...100).contains(value), (0...100).contains(lower), (0...100).contains(upper),
              lower <= value, value <= upper else {
            return "invalid_range"
        }
        guard (0...1).contains(input.coverage) else { return "invalid_coverage" }
        guard input.referenceScale == referenceScale else { return "reference_scale_mismatch" }
        guard input.modelVersion == modelVersion else { return "model_version_mismatch" }
        guard input.confidence != .unavailable else { return "invalid_confidence" }
        guard !uniqueSorted(input.evidenceIDs).isEmpty else { return "missing_evidence" }
        guard !uniqueSorted(input.explanationReceipts).isEmpty else { return "missing_receipt" }
        let width = upper - lower
        if input.sourceClass == .structuredSelfReport && width < 30 { return "band_too_narrow" }
        if input.sourceClass == .legacyUnverified && width < 40 { return "band_too_narrow" }
        if input.sourceClass == .composite { return "invalid_source" }
        return nil
    }

    private static func composite(
        _ domain: String,
        estimates: [FitnessBrainV2CapacityEstimate],
        asOf: String,
        coverage: Double
    ) -> FitnessBrainV2CapacityEstimate {
        let known = estimates.filter { $0.value != nil }
        guard !known.isEmpty else { return unavailableEstimate(domain, asOf: asOf, coverage: coverage) }
        let value = average(known.compactMap(\.value))
        return FitnessBrainV2CapacityEstimate(
            domain: domain,
            value: round4(value),
            lowerBound: round4(average(known.compactMap(\.lowerBound))),
            upperBound: round4(average(known.compactMap(\.upperBound))),
            referenceScale: referenceScale,
            confidence: minimumConfidence(known.map(\.confidence)),
            coverage: round4(coverage),
            freshness: worstFreshness(known.map(\.freshness)),
            sourceClass: .composite,
            evidenceIDs: uniqueSorted(known.flatMap(\.evidenceIDs)),
            explanationReceipts: uniqueSorted(known.flatMap(\.explanationReceipts)),
            modelVersion: modelVersion,
            asOf: asOf,
            band: capacityBand(value)
        )
    }

    private static func unavailableEstimate(
        _ domain: String,
        asOf: String,
        coverage: Double = 0,
        freshness: FBV2Freshness = .stale
    ) -> FitnessBrainV2CapacityEstimate {
        FitnessBrainV2CapacityEstimate(
            domain: domain,
            value: nil,
            lowerBound: nil,
            upperBound: nil,
            referenceScale: referenceScale,
            confidence: .unavailable,
            coverage: round4(coverage),
            freshness: freshness,
            sourceClass: .composite,
            evidenceIDs: [],
            explanationReceipts: [],
            modelVersion: modelVersion,
            asOf: asOf,
            band: .buildingBaseline
        )
    }

    private static func composeReadiness(
        _ signals: [FitnessBrainV2ReadinessSignalInput]
    ) -> FitnessBrainV2Readiness {
        var seen = Set<String>()
        let valid = signals.filter { signal in
            guard !signal.evidenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !seen.contains(signal.evidenceID), signal.normalizedValue.isFinite,
                  (0...100).contains(signal.normalizedValue), signal.confidence != .unavailable
            else { return false }
            seen.insert(signal.evidenceID)
            return true
        }
        let coverage = round4(min(1, Double(valid.count) / 4))
        let freshness = worstFreshness(valid.map(\.freshness))
        guard valid.count >= 2 else {
            return FitnessBrainV2Readiness(
                value: nil,
                confidence: .unavailable,
                coverage: coverage,
                freshness: freshness,
                band: .buildingBaseline,
                evidenceIDs: uniqueSorted(valid.map(\.evidenceID))
            )
        }
        let value = round4(average(valid.map(\.normalizedValue)))
        let confidence = minimumConfidence(valid.map { signal in
            minimumConfidence([signal.confidence, freshnessConfidenceCap[signal.freshness] ?? .low])
        })
        let band: FBV2ReadinessBand = value < 40 ? .reduced : value < 70 ? .mixed : value < 85 ? .ready : .strong
        return FitnessBrainV2Readiness(
            value: value,
            confidence: confidence,
            coverage: coverage,
            freshness: freshness,
            band: band,
            evidenceIDs: uniqueSorted(valid.map(\.evidenceID))
        )
    }

    private static func composeAdherence(
        _ events: [FitnessBrainV2AdherenceEventInput]
    ) -> FitnessBrainV2Adherence {
        var seen = Set<String>()
        var xp = 0
        for event in events {
            guard !event.receiptID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !seen.contains(event.receiptID), event.xp.isFinite,
                  event.xp >= 0, event.xp <= 100 else { continue }
            seen.insert(event.receiptID)
            xp += Int(event.xp.rounded())
        }
        return FitnessBrainV2Adherence(xp: xp, receiptIDs: seen.sorted())
    }

    private static func composeAdaptation(
        _ signals: [FitnessBrainV2AdaptationSignalInput]
    ) -> FitnessBrainV2AdaptationSupport {
        var seen = Set<String>()
        let valid = signals.filter { signal in
            guard !signal.receiptID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !seen.contains(signal.receiptID) else { return false }
            seen.insert(signal.receiptID)
            return true
        }
        let supportive = uniqueSorted(valid.filter { $0.status == .supportive }.map(\.receiptID))
        let limiting = uniqueSorted(valid.filter { $0.status == .limiting }.map(\.receiptID))
        let band: FBV2AdaptationBand
        if valid.isEmpty { band = .unknown }
        else if supportive.count >= 3 && limiting.isEmpty { band = .strong }
        else if supportive.count >= limiting.count { band = .supported }
        else { band = .limited }
        return FitnessBrainV2AdaptationSupport(
            band: band,
            coverage: round4(min(1, Double(valid.count) / 4)),
            supportiveReceiptIDs: supportive,
            limitingReceiptIDs: limiting
        )
    }

    private static func capacityBand(_ value: Double?) -> FBV2CapacityBand {
        guard let value else { return .buildingBaseline }
        if value < 25 { return .foundation }
        if value < 45 { return .developing }
        if value < 65 { return .capable }
        if value < 85 { return .strong }
        return .exceptional
    }

    private static func minimumConfidence(_ values: [FBV2Confidence]) -> FBV2Confidence {
        guard !values.isEmpty else { return .unavailable }
        return values.min { lhs, rhs in
            (confidenceRank[lhs] ?? 0) < (confidenceRank[rhs] ?? 0)
        } ?? .unavailable
    }

    private static func worstFreshness(_ values: [FBV2Freshness]) -> FBV2Freshness {
        guard !values.isEmpty else { return .stale }
        return values.max { lhs, rhs in
            (freshnessRank[lhs] ?? 0) < (freshnessRank[rhs] ?? 0)
        } ?? .stale
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })).sorted()
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func round4(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    private static func optionalRound4(_ value: Double?) -> Double? {
        value.map(round4)
    }
}
