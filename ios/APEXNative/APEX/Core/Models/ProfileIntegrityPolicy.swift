import Foundation

enum ProfileIntegrityPolicy {
    enum Kind: String, Codable, Sendable {
        case standard
        case bespoke
    }

    enum ProtocolID: String, Codable, Sendable {
        case constantineV85 = "constantine-v8.5"
        case juneV84 = "june-v8.4"
        case matthewV1 = "matthew-v1"
        case iulianV2 = "iulian-v2"
    }

    enum BodyFatSource: String, Codable, Sendable {
        case dexa
        case biaScale = "bia_scale"
        case calipers
        case professionalEstimate = "professional_estimate"
        case selfEstimate = "self_estimate"
        case legacyUnverified = "legacy_unverified"
    }

    struct Resolution: Equatable, Sendable {
        let kind: Kind
        let protocolID: ProtocolID?
    }

    private static let protectedOwners: [UUID: (Persona, ProtocolID)] = [
        UUID(uuidString: "9a0fffbc-bb02-40ac-834a-d4e339b32574")!: (.constantine, .constantineV85),
        UUID(uuidString: "f1cc8158-0480-47c9-a2f1-bd03890182f9")!: (.june, .juneV84),
        UUID(uuidString: "ed1fa9d3-9d39-4d39-9b66-a51f2d140492")!: (.matthew, .matthewV1),
        UUID(uuidString: "ce883869-fe72-4371-9788-5723d76f07b5")!: (.iulian, .iulianV2),
    ]

    private static let energyEligibleSources: Set<BodyFatSource> = [
        .dexa, .biaScale, .calipers, .professionalEstimate,
    ]

    static func authorizedProtocol(
        userID: UUID,
        persona: Persona,
        kind: Kind?,
        protocolID: ProtocolID?
    ) -> ProtocolID? {
        guard kind == .bespoke,
              let protocolID,
              let expected = protectedOwners[userID],
              expected.0 == persona,
              expected.1 == protocolID
        else { return nil }
        return protocolID
    }

    static func authorizedProtocol(for profile: Profile) -> ProtocolID? {
        authorizedProtocol(
            userID: profile.userID,
            persona: profile.persona,
            kind: profile.profileKind,
            protocolID: profile.bespokeProtocolID
        )
    }

    static func resolve(_ profile: Profile) -> Resolution {
        guard let protocolID = authorizedProtocol(for: profile) else {
            return Resolution(kind: .standard, protocolID: nil)
        }
        return Resolution(kind: .bespoke, protocolID: protocolID)
    }

    static func isBodyFatEnergyEligible(_ profile: Profile) -> Bool {
        isBodyFatEnergyEligible(
            value: profile.bodyFatPercent,
            source: profile.bodyFatSource
        )
    }

    static func isBodyFatEnergyEligible(
        value: Double?,
        source: BodyFatSource?
    ) -> Bool {
        guard let value,
              value.isFinite,
              (2...70).contains(value),
              let source
        else { return false }
        return energyEligibleSources.contains(source)
    }
}
