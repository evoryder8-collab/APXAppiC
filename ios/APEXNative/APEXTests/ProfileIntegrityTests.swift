import XCTest
@testable import APEX

final class ProfileIntegrityTests: XCTestCase {
    func testProfileCreationExplicitlyRequestsAStandardUnknownBaseline() throws {
        let request = ProfileCreationRequest(userID: UUID(), goal: "maintain")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )

        XCTAssertEqual(object["profile_kind"] as? String, "standard")
        XCTAssertNil(object["bespoke_protocol_id"])
        XCTAssertNil(object["body_fat_pct"])
        XCTAssertNil(object["body_fat_source"])
    }

    func testConstantinePresentationCannotAuthorizeAnOrdinaryAccount() {
        let ordinary = profile(persona: .constantine)
        let targets = EnergyEngine.targets(profile: ordinary, logs: [], catalog: [])

        XCTAssertFalse(EnergyEngine.usesPersonalProtocol(ordinary))
        XCTAssertNotEqual(targets.targetCalories, 2_450)
    }

    func testOnlyTheExactProtectedOwnerReceivesTheConstantineProtocol() {
        let protectedID = UUID(uuidString: "9a0fffbc-bb02-40ac-834a-d4e339b32574")!
        let exact = profile(
            userID: protectedID,
            persona: .constantine,
            kind: .bespoke,
            protocolID: .constantineV85
        )
        let wrongOwner = profile(
            persona: .constantine,
            kind: .bespoke,
            protocolID: .constantineV85
        )

        XCTAssertTrue(EnergyEngine.usesPersonalProtocol(exact))
        XCTAssertEqual(EnergyEngine.targets(profile: exact, logs: [], catalog: []).targetCalories, 2_450)
        XCTAssertFalse(EnergyEngine.usesPersonalProtocol(wrongOwner))
    }

    func testEveryProtectedAccountRequiresItsExactOwnerPersonaAndProtocol() {
        let fixtures: [(String, Persona, ProfileIntegrityPolicy.ProtocolID)] = [
            ("9a0fffbc-bb02-40ac-834a-d4e339b32574", .constantine, .constantineV85),
            ("f1cc8158-0480-47c9-a2f1-bd03890182f9", .june, .juneV84),
            ("ed1fa9d3-9d39-4d39-9b66-a51f2d140492", .matthew, .matthewV1),
            ("ce883869-fe72-4371-9788-5723d76f07b5", .iulian, .iulianV2),
        ]

        for (rawID, persona, protocolID) in fixtures {
            let exact = profile(
                userID: UUID(uuidString: rawID)!, persona: persona,
                kind: .bespoke, protocolID: protocolID
            )
            let impostor = profile(persona: persona, kind: .bespoke, protocolID: protocolID)
            XCTAssertEqual(ProfileIntegrityPolicy.authorizedProtocol(for: exact), protocolID)
            XCTAssertNil(ProfileIntegrityPolicy.authorizedProtocol(for: impostor))
        }
    }

    func testFitnessBrainParityTargetPathUsesTheSameAuthorizationBoundary() {
        var ordinary = FBProfile(
            userID: UUID().uuidString, persona: .constantine, sex: "male",
            weightKG: 71, bodyFatPct: 22.5, customBMR: 1_680,
            heightCM: 177, birthdate: "1992-07-25", activityLevel: .moderate,
            goal: .recomp, baselineDate: "2026-01-01",
            profileKind: "standard", bodyFatSource: "dexa"
        )
        XCTAssertNotEqual(
            FitnessBrainTargets.computeTargets(ordinary, asOf: "2026-08-30").kcal,
            2_450
        )

        ordinary.userID = "9a0fffbc-bb02-40ac-834a-d4e339b32574"
        ordinary.profileKind = "bespoke"
        ordinary.bespokeProtocolID = "constantine-v8.5"
        XCTAssertEqual(
            FitnessBrainTargets.computeTargets(ordinary, asOf: "2026-08-30").kcal,
            2_450
        )
    }

    func testOnlyMeasuredBodyFatCanSelectTheLeanMassEquation() {
        let unknown = profile(bodyFat: nil, source: nil)
        let selfEstimated = profile(bodyFat: 20, source: .selfEstimate)
        let measured = profile(bodyFat: 20, source: .dexa)

        XCTAssertEqual(EnergyEngine.bmr(for: unknown), EnergyEngine.bmr(for: selfEstimated))
        XCTAssertNotEqual(EnergyEngine.bmr(for: measured), EnergyEngine.bmr(for: selfEstimated))
        XCTAssertFalse(ProfileIntegrityPolicy.isBodyFatEnergyEligible(selfEstimated))
        XCTAssertTrue(ProfileIntegrityPolicy.isBodyFatEnergyEligible(measured))
    }

    func testLegacyProfileDecodingFailsClosedWithoutDiscardingBodyFat() throws {
        let encoded = try JSONEncoder().encode(profile(bodyFat: 23, source: .legacyUnverified))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "profile_kind")
        object.removeValue(forKey: "bespoke_protocol_id")
        object.removeValue(forKey: "body_fat_source")
        let decoded = try JSONDecoder().decode(
            Profile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.bodyFatPercent, 23)
        XCTAssertEqual(ProfileIntegrityPolicy.resolve(decoded).kind, .standard)
        XCTAssertFalse(ProfileIntegrityPolicy.isBodyFatEnergyEligible(decoded))
    }

    func testRemoteProfilePayloadPersistsAStandardPolicyAndExplicitBodyFatClear() throws {
        let value = profile(bodyFat: nil, source: nil)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(try RemoteProfilePayload(value))
            ) as? [String: Any]
        )

        XCTAssertEqual(object["profile_kind"] as? String, "standard")
        XCTAssertTrue(object["bespoke_protocol_id"] is NSNull)
        XCTAssertTrue(object["body_fat_pct"] is NSNull)
        XCTAssertTrue(object["body_fat_source"] is NSNull)
        XCTAssertNil(object["custom_bmr"])
    }

    private func profile(
        userID: UUID = UUID(),
        persona: Persona = .constantine,
        kind: ProfileIntegrityPolicy.Kind = .standard,
        protocolID: ProfileIntegrityPolicy.ProtocolID? = nil,
        bodyFat: Double? = 20,
        source: ProfileIntegrityPolicy.BodyFatSource? = .legacyUnverified
    ) -> Profile {
        Profile(
            id: userID, userID: userID, persona: persona,
            profileKind: kind, bespokeProtocolID: protocolID,
            displayName: "APEX Athlete", sex: "male", weightKG: 80,
            bodyFatPercent: bodyFat, bodyFatSource: source, bodyFatMeasuredAt: nil,
            customBMR: nil, heightCM: 180, birthdate: "1990-01-01",
            activityLevel: .moderate, goal: .recomp,
            targetKcal: nil, targetProteinG: nil, targetFatG: nil, targetCarbsG: nil,
            trainingTime: "07:00", baselineDate: "2026-01-01", profileNote: "",
            seedVersion: 1, calibrationK: 1, calibrationHistory: [],
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }
}
