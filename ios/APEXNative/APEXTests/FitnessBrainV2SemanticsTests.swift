import XCTest
@testable import APEX

final class FitnessBrainV2SemanticsTests: XCTestCase {
    func testSharedParityScenarios() throws {
        let fixture: FitnessBrainV2Fixture = try decodeFixture()

        for scenario in fixture.scenarios {
            let result = FitnessBrainV2.compose(scenario.input)
            XCTAssertEqual(
                FitnessBrainV2.summarize(result),
                scenario.expected,
                "Scenario failed: \(scenario.name)"
            )
        }
    }

    func testContextLayersCannotRewriteCapacity() throws {
        let fixture: FitnessBrainV2Fixture = try decodeFixture()
        let supported = try XCTUnwrap(fixture.scenarios.first { $0.name.hasPrefix("supported core") })
        let first = FitnessBrainV2.compose(supported.input)
        var altered = supported.input
        altered.readinessSignals = [
            .init(kind: "sleep", normalizedValue: 10, confidence: .low, freshness: .current, evidenceID: "sleep-low"),
            .init(kind: "fatigue", normalizedValue: 15, confidence: .low, freshness: .current, evidenceID: "fatigue-low")
        ]
        altered.adherenceEvents = []
        altered.adaptationSignals = [
            .init(kind: "protein", status: .limiting, receiptID: "protein-low"),
            .init(kind: "hydration", status: .limiting, receiptID: "hydration-low")
        ]
        altered.healthContext = .init(flags: [.acuteSymptom, .clearanceRequired], receiptIDs: ["safety-1"])
        let second = FitnessBrainV2.compose(altered)

        XCTAssertEqual(second.capacity, first.capacity)
        XCTAssertNotEqual(second.readiness, first.readiness)
        XCTAssertEqual(second.adherence.xp, 0)
        XCTAssertFalse(second.healthContext.fieldTestEligible)
    }

    func testV2TypesCarryNoProfileOrProtocolAuthority() throws {
        let sourceURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "fitness-brain-v2-semantics",
            withExtension: "json"
        ))
        let fixtureSource = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(fixtureSource.contains("persona"))
        XCTAssertFalse(fixtureSource.contains("bespoke_protocol"))
        XCTAssertFalse(fixtureSource.contains("target_kcal"))
    }

    private func decodeFixture<T: Decodable>() throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "fitness-brain-v2-semantics",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
