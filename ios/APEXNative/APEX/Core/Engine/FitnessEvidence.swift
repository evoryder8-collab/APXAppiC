import Foundation

enum FitnessEvidenceAdmission: String, Codable, Sendable, Equatable {
    case trusted
    case user
}

enum FitnessEvidenceConfidence: String, Codable, Sendable, Equatable, Hashable {
    case low
    case medium
    case high
}

enum FitnessEvidenceMetric: String, Codable, Sendable, Equatable, Hashable {
    case bodyMass = "body_mass"
    case height
    case bodyFatPercentage = "body_fat_percentage"
    case restingMetabolicRate = "resting_metabolic_rate"
    case vo2Max = "vo2_max"
    case restingHeartRate = "resting_heart_rate"
    case waistCircumference = "waist_circumference"
    case cardioCapacityScore = "cardio_capacity_score"
    case upperBodyStrengthScore = "upper_body_strength_score"
    case lowerBodyStrengthScore = "lower_body_strength_score"
    case flexibilityScore = "flexibility_score"
    case jointHealthScore = "joint_health_score"
    case balanceScore = "balance_score"
}

enum FitnessEvidenceSource: String, Codable, Sendable, Equatable, Hashable {
    case indirectCalorimetry = "indirect_calorimetry"
    case dexaMeasurement = "dexa_measurement"
    case dexaDerivedEstimate = "dexa_derived_estimate"
    case clinicalMeasurement = "clinical_measurement"
    case supportedDevice = "supported_device"
    case guidedAPEXFieldTest = "guided_apex_field_test"
    case structuredSelfReport = "structured_self_report"
    case userEnteredExternalResult = "user_entered_external_result"
    case legacyUnverified = "legacy_unverified"
}

struct FitnessEvidenceDraft: Codable, Sendable, Equatable {
    var userID: String
    var metric: String
    var value: Double
    var unit: String
    var source: String
    var `protocol`: String?
    var device: String?
    var measuredAt: String
    var importedAt: String
    var requestedConfidence: String
    var metadata: JSONValue
    var supersedesID: String?
    var clientIdempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case metric, value, unit, source, `protocol`, device, metadata
        case measuredAt = "measured_at"
        case importedAt = "imported_at"
        case requestedConfidence = "requested_confidence"
        case supersedesID = "supersedes_id"
        case clientIdempotencyKey = "client_idempotency_key"
    }
}

struct FitnessEvidencePredecessor: Codable, Sendable, Equatable {
    var id: String
    var userID: String
    var metric: String

    enum CodingKeys: String, CodingKey {
        case id, metric
        case userID = "user_id"
    }
}

struct NormalizedFitnessEvidence: Sendable, Equatable {
    var userID: String
    var metric: FitnessEvidenceMetric
    var value: Double
    var unit: String
    var source: FitnessEvidenceSource
    var `protocol`: String?
    var device: String?
    var measuredAt: String
    var importedAt: String
    var confidence: FitnessEvidenceConfidence
    var metadata: [String: JSONValue]
    var supersedesID: String?
    var clientIdempotencyKey: String
}

struct RecordUserFitnessEvidenceParameters: Encodable, Sendable {
    let pMetric: String
    let pValue: Double
    let pUnit: String
    let pMeasuredAt: String
    let pClientIdempotencyKey: String
    let pSource: String
    let pProtocol: String?
    let pDevice: String?
    let pMetadata: [String: JSONValue]
    let pSupersedesID: UUID?

    init(_ evidence: NormalizedFitnessEvidence) {
        pMetric = evidence.metric.rawValue
        pValue = evidence.value
        pUnit = evidence.unit
        pMeasuredAt = evidence.measuredAt
        pClientIdempotencyKey = evidence.clientIdempotencyKey
        pSource = evidence.source.rawValue
        pProtocol = evidence.protocol
        pDevice = evidence.device
        pMetadata = evidence.metadata
        pSupersedesID = evidence.supersedesID.flatMap(UUID.init(uuidString:))
    }

    enum CodingKeys: String, CodingKey {
        case pMetric = "p_metric"
        case pValue = "p_value"
        case pUnit = "p_unit"
        case pMeasuredAt = "p_measured_at"
        case pClientIdempotencyKey = "p_client_idempotency_key"
        case pSource = "p_source"
        case pProtocol = "p_protocol"
        case pDevice = "p_device"
        case pMetadata = "p_metadata"
        case pSupersedesID = "p_supersedes_id"
    }
}

enum FitnessEvidenceRecordingError: Error, Sendable {
    case accountMismatch
    case trustedSourceRequiresIngestion
}

struct FitnessEvidenceNormalizationSummary: Codable, Sendable, Equatable {
    var metric: FitnessEvidenceMetric
    var value: Double
    var unit: String
    var source: FitnessEvidenceSource
    var confidence: FitnessEvidenceConfidence
    var `protocol`: String?
    var device: String?
    var measuredAt: String
    var importedAt: String
    var metadataKeys: [String]
    var supersedesID: String?
    var clientIdempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case metric, value, unit, source, confidence, `protocol`, device
        case measuredAt = "measured_at"
        case importedAt = "imported_at"
        case metadataKeys = "metadata_keys"
        case supersedesID = "supersedes_id"
        case clientIdempotencyKey = "client_idempotency_key"
    }
}

struct FitnessEvidenceNormalizationExpected: Codable, Sendable, Equatable {
    var status: String
    var summary: FitnessEvidenceNormalizationSummary?
    var reason: String?
}

struct FitnessEvidenceNormalizationFixture: Codable, Sendable {
    struct Scenario: Codable, Sendable {
        var name: String
        var admission: FitnessEvidenceAdmission
        var input: FitnessEvidenceDraft
        var predecessor: FitnessEvidencePredecessor?
        var expected: FitnessEvidenceNormalizationExpected
    }

    var referenceNow: String
    var scenarios: [Scenario]

    enum CodingKeys: String, CodingKey {
        case referenceNow = "reference_now"
        case scenarios
    }
}

enum FitnessEvidenceNormalizationResult: Sendable, Equatable {
    case accepted(NormalizedFitnessEvidence)
    case rejected(String)
}

enum FitnessEvidenceNormalizer {
    private static let metricAliases: [String: FitnessEvidenceMetric] = [
        "body_mass": .bodyMass,
        "body_weight": .bodyMass,
        "weight": .bodyMass,
        "weight_kg": .bodyMass,
        "height": .height,
        "height_cm": .height,
        "body_fat": .bodyFatPercentage,
        "body_fat_pct": .bodyFatPercentage,
        "body_fat_percentage": .bodyFatPercentage,
        "bmr": .restingMetabolicRate,
        "rmr": .restingMetabolicRate,
        "resting_metabolic_rate": .restingMetabolicRate,
        "vo2_max": .vo2Max,
        "vo2max": .vo2Max,
        "resting_heart_rate": .restingHeartRate,
        "resting_hr": .restingHeartRate,
        "waist": .waistCircumference,
        "waist_circumference": .waistCircumference,
        "cardio_capacity_score": .cardioCapacityScore,
        "upper_body_strength_score": .upperBodyStrengthScore,
        "lower_body_strength_score": .lowerBodyStrengthScore,
        "flexibility_score": .flexibilityScore,
        "joint_health_score": .jointHealthScore,
        "balance_score": .balanceScore
    ]

    private static let sourceAliases: [String: FitnessEvidenceSource] = [
        "indirect_calorimetry": .indirectCalorimetry,
        "metabolic_cart": .indirectCalorimetry,
        "dexa": .dexaMeasurement,
        "dexa_scan": .dexaMeasurement,
        "dexa_measurement": .dexaMeasurement,
        "dexa_derived": .dexaDerivedEstimate,
        "dexa_derived_estimate": .dexaDerivedEstimate,
        "clinical": .clinicalMeasurement,
        "clinical_measurement": .clinicalMeasurement,
        "supported_device": .supportedDevice,
        "apple_health": .supportedDevice,
        "apple_watch": .supportedDevice,
        "healthkit": .supportedDevice,
        "guided_apex_field_test": .guidedAPEXFieldTest,
        "apex_field_test": .guidedAPEXFieldTest,
        "structured_self_report": .structuredSelfReport,
        "self_report": .structuredSelfReport,
        "user_entered_external_result": .userEnteredExternalResult,
        "external_result": .userEnteredExternalResult,
        "legacy_unverified": .legacyUnverified,
        "legacy": .legacyUnverified
    ]

    private static let unitAliases: [String: String] = [
        "kg": "kg",
        "cm": "cm",
        "percent": "percent",
        "pct": "percent",
        "%": "percent",
        "kcal_per_day": "kcal_per_day",
        "kcal/day": "kcal_per_day",
        "ml_per_kg_min": "ml_per_kg_min",
        "ml/kg/min": "ml_per_kg_min",
        "bpm": "bpm",
        "beats_per_minute": "bpm",
        "score_0_100": "score_0_100"
    ]

    private static let trustedSources: Set<FitnessEvidenceSource> = [
        .indirectCalorimetry,
        .dexaMeasurement,
        .dexaDerivedEstimate,
        .clinicalMeasurement,
        .supportedDevice,
        .guidedAPEXFieldTest
    ]

    private static let confidenceRank: [FitnessEvidenceConfidence: Int] = [
        .low: 0,
        .medium: 1,
        .high: 2
    ]

    private static let confidenceCeiling: [FitnessEvidenceSource: FitnessEvidenceConfidence] = [
        .indirectCalorimetry: .high,
        .dexaMeasurement: .high,
        .dexaDerivedEstimate: .medium,
        .clinicalMeasurement: .high,
        .supportedDevice: .medium,
        .guidedAPEXFieldTest: .medium,
        .structuredSelfReport: .low,
        .userEnteredExternalResult: .low,
        .legacyUnverified: .low
    ]

    private enum OptionalTextResult {
        case valid(String?)
        case invalid
    }

    static func normalize(
        _ input: FitnessEvidenceDraft,
        admission: FitnessEvidenceAdmission,
        referenceNow: String,
        predecessor: FitnessEvidencePredecessor? = nil
    ) -> FitnessEvidenceNormalizationResult {
        let userID = input.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else { return .rejected("invalid_owner") }

        guard let metric = metricAliases[token(input.metric)] else {
            return .rejected("unsupported_metric")
        }
        guard let submittedSource = sourceAliases[token(input.source)] else {
            return .rejected("unsupported_source")
        }
        guard let unit = normalizeUnit(input.unit), valid(metric: metric, unit: unit, value: input.value) else {
            return .rejected("invalid_unit_or_range")
        }
        guard case .object(let metadata) = input.metadata else {
            return .rejected("invalid_metadata")
        }

        guard
            let measured = parseDate(input.measuredAt),
            let imported = parseDate(input.importedAt),
            let reference = parseDate(referenceNow)
        else {
            return .rejected("invalid_timestamp")
        }
        let oneDay: TimeInterval = 24 * 60 * 60
        let earliest = parseDate("1900-01-01T00:00:00Z") ?? .distantPast
        guard
            measured >= earliest,
            measured <= imported.addingTimeInterval(oneDay),
            imported <= reference.addingTimeInterval(oneDay)
        else {
            return .rejected("invalid_timestamp")
        }

        let clientKey = input.clientIdempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientKey.isEmpty, clientKey.count <= 160 else {
            return .rejected("invalid_idempotency_key")
        }

        let protocolResult = optionalText(input.protocol, maximum: 160)
        let deviceResult = optionalText(input.device, maximum: 200)
        guard
            case .valid(let submittedProtocol) = protocolResult,
            case .valid(let device) = deviceResult
        else {
            return .rejected("invalid_text_field")
        }

        var source = submittedSource
        var normalizedProtocol = submittedProtocol
        if admission == .user, trustedSources.contains(submittedSource) {
            source = .userEnteredExternalResult
            normalizedProtocol = normalizedProtocol ?? "reported:\(submittedSource.rawValue)"
        } else if admission == .user, submittedSource == .legacyUnverified {
            source = .userEnteredExternalResult
            normalizedProtocol = normalizedProtocol ?? "reported:legacy_unverified"
        }

        guard let requested = FitnessEvidenceConfidence(rawValue: input.requestedConfidence),
              let ceiling = confidenceCeiling[source],
              let requestedRank = confidenceRank[requested],
              let ceilingRank = confidenceRank[ceiling]
        else {
            return .rejected("invalid_confidence")
        }
        let confidence = requestedRank <= ceilingRank ? requested : ceiling

        let supersedesID = input.supersedesID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        if let supersedesID {
            let predecessorMetric = predecessor.flatMap { metricAliases[token($0.metric)] }
            guard
                let predecessor,
                predecessor.id == supersedesID,
                predecessor.userID == userID,
                predecessorMetric == metric
            else {
                return .rejected("invalid_correction")
            }
        }

        return .accepted(NormalizedFitnessEvidence(
            userID: userID,
            metric: metric,
            value: input.value,
            unit: unit,
            source: source,
            protocol: normalizedProtocol,
            device: device,
            measuredAt: formatDate(measured),
            importedAt: formatDate(imported),
            confidence: confidence,
            metadata: metadata,
            supersedesID: supersedesID,
            clientIdempotencyKey: clientKey
        ))
    }

    static func summarize(_ result: FitnessEvidenceNormalizationResult) -> FitnessEvidenceNormalizationExpected {
        switch result {
        case .rejected(let reason):
            return FitnessEvidenceNormalizationExpected(status: "rejected", summary: nil, reason: reason)
        case .accepted(let evidence):
            return FitnessEvidenceNormalizationExpected(
                status: "accepted",
                summary: FitnessEvidenceNormalizationSummary(
                    metric: evidence.metric,
                    value: evidence.value,
                    unit: evidence.unit,
                    source: evidence.source,
                    confidence: evidence.confidence,
                    protocol: evidence.protocol,
                    device: evidence.device,
                    measuredAt: evidence.measuredAt,
                    importedAt: evidence.importedAt,
                    metadataKeys: evidence.metadata.keys.sorted(),
                    supersedesID: evidence.supersedesID,
                    clientIdempotencyKey: evidence.clientIdempotencyKey
                ),
                reason: nil
            )
        }
    }

    private static func token(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        var previousWasSeparator = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar.value == 37 {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !result.isEmpty {
                result.append("_")
                previousWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func normalizeUnit(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return unitAliases[raw] ?? unitAliases[token(raw)]
    }

    private static func valid(metric: FitnessEvidenceMetric, unit: String, value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch metric {
        case .bodyMass:
            return unit == "kg" && (10...500).contains(value)
        case .height:
            return unit == "cm" && (50...260).contains(value)
        case .bodyFatPercentage:
            return unit == "percent" && (2...70).contains(value)
        case .restingMetabolicRate:
            return unit == "kcal_per_day" && (400...8000).contains(value)
        case .vo2Max:
            return unit == "ml_per_kg_min" && (5...120).contains(value)
        case .restingHeartRate:
            return unit == "bpm" && (20...250).contains(value)
        case .waistCircumference:
            return unit == "cm" && (30...300).contains(value)
        case .cardioCapacityScore,
             .upperBodyStrengthScore,
             .lowerBodyStrengthScore,
             .flexibilityScore,
             .jointHealthScore,
             .balanceScore:
            return unit == "score_0_100" && (0...100).contains(value)
        }
    }

    private static func optionalText(_ value: String?, maximum: Int) -> OptionalTextResult {
        guard let value else { return .valid(nil) }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .valid(nil) }
        guard trimmed.count <= maximum else { return .invalid }
        return .valid(trimmed)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }

    private static func formatDate(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
