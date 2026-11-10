import Foundation
import XCTest
@testable import APEX

@MainActor
final class WaterVolumeComparisonTests: XCTestCase {
    private struct Landmark: Decodable {
        let name: String
        let singular: String
        let plural: String?
        let litres: Double
        let translations: [String: String]
    }

    private func bundledLandmarks() throws -> [Landmark] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "water-volume-landmarks", withExtension: "json"))
        return try JSONDecoder().decode([Landmark].self, from: Data(contentsOf: url))
    }

    private func withLanguage(_ language: AppLanguage, _ body: () throws -> Void) rethrows {
        let state = LanguageState.shared
        let previous = state.language
        defer { state.language = previous }
        state.language = language
        try body()
    }

    func testCatalogueIsLargeUniqueAscendingAndFullyTranslated() throws {
        let landmarks = try bundledLandmarks()
        XCTAssertGreaterThanOrEqual(landmarks.count, 150)
        XCTAssertEqual(WaterVolumeComparison.count, landmarks.count)
        XCTAssertEqual(Set(landmarks.map(\.name)).count, landmarks.count)
        for (smaller, larger) in zip(landmarks, landmarks.dropFirst()) {
            XCTAssertLessThan(smaller.litres, larger.litres, "\(smaller.name) before \(larger.name)")
        }
        let languages = ["de", "de-CH", "es", "it", "ja", "pt", "ro", "th"]
        for landmark in landmarks {
            XCTAssertFalse(landmark.singular.isEmpty, landmark.name)
            for language in languages {
                XCTAssertFalse(landmark.translations[language]?.isEmpty ?? true, "\(landmark.name) \(language)")
            }
        }
    }

    func testEveryEverydayTotalHasACloseSingleOrCountedMatch() throws {
        let landmarks = try bundledLandmarks()
        let countable = Set(landmarks.filter { $0.plural != nil }.map(\.litres))
        try withLanguage(.english) {
            for step in 0...200 {
                let total = 0.25 * pow(20_000, Double(step) / 200)
                let match = try XCTUnwrap(WaterVolumeComparison.caption(litres: total))
                let count = try XCTUnwrap(match.count, "\(total) L fell back to a milestone")
                XCTAssertEqual(abs(Double(count) * match.litres - total) / total, 0, accuracy: 0.3, "\(total) L")
                XCTAssertTrue(match.caption.hasPrefix("Enough to fill "), match.caption)
                if count > 1 {
                    XCTAssertTrue(countable.contains(match.litres), "\(match.name) has no plural")
                }
            }
        }
    }

    func testCaptionsReadNaturallyAndLocalize() throws {
        try withLanguage(.english) {
            XCTAssertEqual(WaterVolumeComparison.caption(litres: 150)?.caption, "Enough to fill a bathtub")
            XCTAssertEqual(WaterVolumeComparison.caption(litres: 300)?.caption, "Enough to fill a fridge")
            XCTAssertEqual(WaterVolumeComparison.caption(litres: 50_000e12)?.caption, "Lake Baikal · You have passed this volume")
            XCTAssertNil(WaterVolumeComparison.caption(litres: 0))
            XCTAssertNil(WaterVolumeComparison.caption(litres: -1))
            XCTAssertNil(WaterVolumeComparison.caption(litres: .infinity))
            XCTAssertNil(WaterVolumeComparison.caption(litres: .nan))
        }
        try withLanguage(.german) {
            let bathtub = try XCTUnwrap(WaterVolumeComparison.caption(litres: 150))
            XCTAssertEqual(bathtub.name, "Badewanne")
            XCTAssertTrue(bathtub.caption.hasPrefix("Badewanne · "), bathtub.caption)
            XCTAssertEqual(WaterVolumeComparison.next(after: 100)?.name, "Großer Koffer")
        }
    }

    func testACaptionNeverClaimsMoreThanTheTotalAcrossTheWholeCatalogue() throws {
        let landmarks = try bundledLandmarks()
        var totals = landmarks.flatMap { [$0.litres * 0.999, $0.litres, $0.litres * 1.001] }
        for (smaller, larger) in zip(landmarks, landmarks.dropFirst()) {
            totals += (1...9).map { smaller.litres + (larger.litres - smaller.litres) * Double($0) / 10 }
        }
        try withLanguage(.english) {
            XCTAssertEqual(WaterVolumeComparison.caption(litres: 17)?.caption, "Enough to fill a motorcycle fuel tank")
            XCTAssertEqual(WaterVolumeComparison.next(after: 17)?.name, "Water-cooler bottle")
            for total in totals {
                let match = try XCTUnwrap(WaterVolumeComparison.caption(litres: total), "\(total) L")
                let filled = landmarks.last { $0.litres <= total }
                let next = WaterVolumeComparison.next(after: total)
                XCTAssertEqual(next?.litres, landmarks.first { $0.litres > total }?.litres, "\(total) L")
                switch match.count {
                case 1?:
                    XCTAssertEqual(match.litres, filled?.litres, "\(total) L names \(match.name), not the largest it fills")
                    XCTAssertTrue(match.caption.hasPrefix("Enough to fill "), match.caption)
                case let count?:
                    XCTAssertLessThanOrEqual(Double(count) * match.litres, total, "\(total) L does not fill \(count) × \(match.name)")
                    XCTAssertTrue(match.caption.hasPrefix("Enough to fill \(count) "), match.caption)
                case nil:
                    XCTAssertEqual(match.litres, (filled ?? landmarks[0]).litres, "\(total) L")
                    XCTAssertTrue(match.caption.hasSuffix(filled == nil ? "Your next volume" : "You have passed this volume"), match.caption)
                }
            }
        }
    }

    func testNextMilestoneIsStrictlyLargerUntilTheLargest() throws {
        let landmarks = try bundledLandmarks()
        for total in [0.001, 1.0, 150, 30_000, 1e12] {
            let next = try XCTUnwrap(WaterVolumeComparison.next(after: total))
            XCTAssertGreaterThan(next.litres, total)
        }
        XCTAssertEqual(WaterVolumeComparison.next(after: 150)?.litres, 159)
        XCTAssertNil(WaterVolumeComparison.next(after: try XCTUnwrap(landmarks.last).litres))
    }
}
