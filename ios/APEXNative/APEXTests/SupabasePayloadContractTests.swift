import XCTest
@testable import APEX

private struct SupabasePayloadFixture: Decodable {
    let version: Int
    let enums: [String: [String]]
    let structuredMeal: StructuredMealRPCPayload
    let mealPreset: MealPresetRPCPayload

    enum CodingKeys: String, CodingKey {
        case version, enums
        case structuredMeal = "structured_meal"
        case mealPreset = "meal_preset"
    }
}

final class SupabasePayloadContractTests: XCTestCase {
    private static let fixtureData: Data = {
        guard let url = Bundle(for: SupabasePayloadContractTests.self)
            .url(forResource: "supabase-payload-contract", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("supabase-payload-contract.json missing from the test bundle")
        }
        return data
    }()

    private static let fixture = try! JSONDecoder().decode(
        SupabasePayloadFixture.self,
        from: fixtureData
    )

    func testNativeUsesEveryCanonicalSupabaseEnumString() {
        XCTAssertEqual(Self.fixture.version, 1)
        XCTAssertEqual(Self.fixture.enums, SupabaseEnumContract.values)
        assertValues("persona", Persona.allCases.map(\.rawValue))
        assertValues("activity_level", ActivityLevel.allCases.map(\.rawValue))
        assertValues("goal", Goal.allCases.map(\.rawValue))
        assertValues("session_mode", WorkoutSessionMode.allCases.map(\.rawValue))
        assertValues("logged_as", MealLogKind.acceptedValues)
        assertValues("hydration_kind", HydrationKind.allCases.map(\.rawValue))
        assertValues("hydration_preset_kind", HydrationPresetKind.allCases.map(\.rawValue))
        assertValues("hydration_source", HydrationSource.allCases.map(\.rawValue))
        assertValues("hydration_target_mode", HydrationTargetMode.allCases.map(\.rawValue))
        assertValues("activity_input_style", ActivityInputStyle.allCases.map(\.rawValue), fixtureKey: "activity_input_style")
    }

    func testSwiftMealAndPresetRPCPayloadsRoundTripTheSharedFixtureExactly() throws {
        let rawFixture = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Self.fixtureData) as? [String: Any]
        )
        try assertRoundTrip(
            Self.fixture.structuredMeal,
            expected: rawFixture["structured_meal"]
        )
        try assertRoundTrip(
            Self.fixture.mealPreset,
            expected: rawFixture["meal_preset"]
        )
    }

    func testLegacyMealKindCannotEscapeIntoTheCanonicalPayload() {
        for value in MealLogKind.acceptedValues {
            XCTAssertEqual(MealLogKind.normalized(value), value)
        }
        XCTAssertEqual(MealLogKind.normalized("actual"), "custom")
        XCTAssertEqual(MealLogKind.normalized(""), "custom")
    }

    private func assertValues(_ key: String, _ actual: [String], fixtureKey: String? = nil) {
        let expected = Self.fixture.enums[fixtureKey ?? key] ?? []
        XCTAssertEqual(Set(actual), Set(expected), key)
    }

    private func assertRoundTrip<Value: Codable>(_ value: Value, expected: Any?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(value)
        let decodedAgain = try JSONDecoder().decode(Value.self, from: encoded)
        let encodedAgain = try encoder.encode(decodedAgain)
        XCTAssertEqual(try canonicalJSON(encoded), try canonicalJSON(encodedAgain))

        let expectedObject = try XCTUnwrap(expected)
        let expectedData = try JSONSerialization.data(withJSONObject: expectedObject, options: [.sortedKeys])
        XCTAssertEqual(try canonicalJSON(encoded), try canonicalJSON(expectedData))
    }

    private func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
