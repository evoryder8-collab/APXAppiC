/*
 * Golden parity for WeightTrend and ExerciseGuidance against the real
 * TypeScript modules (Tools/generate-training-support-fixtures.mts).
 */
import XCTest
@testable import APEX

private struct SupportFixture: Decodable {
    let weight: WeightFixture
    let cues: [CueCase]
}

private struct WeightFixture: Decodable {
    let anchor: String
    let logs: [LogRow]
    let ranges: [RangeCase]
}

private struct LogRow: Decodable { let date: String; let weight_kg: Double }
private struct RangeCase: Decodable { let range: Int; let points: [PointRow]; let change: Double? }
private struct PointRow: Decodable { let date: String; let weight_kg: Double }
private struct CueCase: Decodable { let name: String; let en: String; let ro: String; let th: String }

final class TrainingSupportParityTests: XCTestCase {
    private static let fixture: SupportFixture = {
        guard let url = Bundle(for: TrainingSupportParityTests.self)
            .url(forResource: "training-support-parity", withExtension: "json"),
            let data = try? Data(contentsOf: url) else {
            fatalError("training-support-parity.json missing from the test bundle")
        }
        return try! JSONDecoder().decode(SupportFixture.self, from: data)
    }()

    private var logs: [DailyLog] {
        Self.fixture.weight.logs.map { row in
            DailyLog(
                id: UUID(), userID: UUID(), date: row.date,
                kcal: nil, proteinG: nil, fatG: nil, carbsG: nil,
                waterL: 0, estimatedTDEE: nil, computedPAL: nil,
                activityMode: "quick", weightKG: row.weight_kg
            )
        }
    }

    func testWeightTrendMatchesTheWeb() {
        for scenario in Self.fixture.weight.ranges {
            guard let range = WeightTrend.Range(rawValue: scenario.range) else {
                return XCTFail("unknown range \(scenario.range)")
            }
            let points = WeightTrend.build(logs: logs, anchorDate: Self.fixture.weight.anchor, range: range)
            XCTAssertEqual(points.map(\.date), scenario.points.map(\.date), "\(scenario.range) day dates")
            for (point, want) in zip(points, scenario.points) {
                XCTAssertEqual(point.weightKG, want.weight_kg, accuracy: 0.0001, point.date)
            }
            /* A single point has no change to report. Comparing through NaN
               would silently pass or silently fail, so nil is checked as nil. */
            let change = WeightTrend.change(points)
            if let expected = scenario.change {
                XCTAssertNotNil(change, "\(scenario.range) day change")
                XCTAssertEqual(change ?? .nan, expected, accuracy: 0.0001, "\(scenario.range) day change")
            } else {
                XCTAssertNil(change, "\(scenario.range) day change should be absent")
            }
        }
    }

    /// Values outside the plausible band are typos or a unit mix-up, and a
    /// weigh-in after the anchor belongs to a day not being shown yet.
    func testImplausibleAndFutureWeighInsAreExcluded() {
        let points = WeightTrend.build(logs: logs, anchorDate: Self.fixture.weight.anchor, range: .year)
        XCTAssertFalse(points.contains { $0.weightKG < 25 || $0.weightKG > 300 })
        XCTAssertFalse(points.contains { $0.date > Self.fixture.weight.anchor })
        /* One date logged twice keeps the last value, so an interrupted sync
           cannot put two readings on the same day. */
        XCTAssertEqual(Set(points.map(\.date)).count, points.count)
    }

    func testExecutionCuesMatchTheWeb() {
        for scenario in Self.fixture.cues {
            XCTAssertEqual(ExerciseGuidance.executionCue(scenario.name, language: .english), scenario.en, scenario.name)
            XCTAssertEqual(ExerciseGuidance.executionCue(scenario.name, language: .romanian), scenario.ro, scenario.name)
            XCTAssertEqual(ExerciseGuidance.executionCue(scenario.name, language: .thai), scenario.th, scenario.name)
        }
    }

    /// The bug this port surfaced: a general movement must never swallow the
    /// specific one whose name contains it.
    func testSpecificMovementsAreNotSwallowedByGeneralOnes() {
        let legCurl = ExerciseGuidance.executionCue("Leg curl", language: .english)
        let bicepsCurl = ExerciseGuidance.executionCue("Biceps curl", language: .english)
        XCTAssertNotEqual(legCurl, bicepsCurl, "a hamstring machine must not get a biceps cue")
        XCTAssertTrue(legCurl.contains("hips"), legCurl)
        XCTAssertTrue(bicepsCurl.contains("upper arm"), bicepsCurl)

        let split = ExerciseGuidance.executionCue("Bulgarian split squat", language: .english)
        let squat = ExerciseGuidance.executionCue("Back squat", language: .english)
        XCTAssertNotEqual(split, squat)
        XCTAssertTrue(split.contains("rear foot"), split)
    }

    func testUnlistedExercisesFallBack() {
        let cue = ExerciseGuidance.executionCue("Something entirely unlisted", language: .english)
        XCTAssertEqual(cue, ExerciseGuidance.fallback.en)
        XCTAssertTrue(cue.contains("pain-free"), cue)
    }
}
